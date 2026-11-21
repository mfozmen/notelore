/// Finding notes by meaning (#929): multilingual-e5-small turns a note and a
/// message into vectors, and the nearest notes join the prompt's note list.
/// The tokenizer and the arithmetic live here; running the model is native
/// (`meaning_native.dart`) behind [Encode], so all of this is tested with fakes.
/// Vectors are derived state in the index, rebuilt from the notes.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'store/index.dart';

/// The model's hidden states for token [ids], `ids.length * dim` floats.
typedef Encode = Float32List Function(List<int> ids);

/// SentencePiece's unigram model as Hugging Face's `tokenizer.json` holds it
/// (XLM-RoBERTa's vocabulary): the split of each word with the best total score.
class Unigram {
  factory Unigram.fromJson(String json) {
    final model = (jsonDecode(json) as Map)['model'] as Map;
    final vocab = model['vocab'] as List;
    final ids = <String, int>{};
    final scores = Float64List(vocab.length);
    var longest = 1;
    var lowest = 0.0;
    for (var i = 0; i < vocab.length; i++) {
      final [piece as String, score as num] = vocab[i] as List;
      ids[piece] = i;
      scores[i] = score.toDouble();
      longest = max(longest, piece.runes.length);
      lowest = min(lowest, scores[i]);
    }
    return Unigram._(ids, scores, longest, model['unk_id'] as int, lowest - 10);
  }

  Unigram._(this._ids, this._scores, this._longest, this._unk, this._unkScore);

  final Map<String, int> _ids;
  final Float64List _scores;
  final int _longest;
  final int _unk;

  /// What an unknown character costs: below any piece, as in SentencePiece.
  final double _unkScore;

  /// [text] as token ids, `<s>` first and `</s>` last, at most [max] of them.
  List<int> encode(String text, {int max = 512}) {
    // shortcut: NFKC and this cleanup stand in for the vocabulary's precompiled
    // nmt_nfkc map; they differ on rare characters such as zero-width spaces.
    // A token is rarely over 16 characters: the rest of a long note would be cut anyway.
    final head = text.length > max * 16 ? text.substring(0, max * 16) : text;
    final clean = unorm
        .nfkc(head)
        .replaceAll(RegExp(r'\s'), ' ')
        .replaceAll(RegExp(r'\p{Cc}', unicode: true), '')
        .replaceAll(RegExp(' {2,}'), ' ');
    if (clean.isEmpty) return [_ids['<s>']!, _ids['</s>']!];
    final marked = (clean.startsWith(' ') ? clean : ' $clean').replaceAll(' ', '▁');
    final ids = [for (final word in RegExp('▁[^▁]*').allMatches(marked)) ..._word(word[0]!)];
    return [_ids['<s>']!, ...ids.take(max - 2), _ids['</s>']!];
  }

  /// Viterbi over [word]'s characters; unknown runs become one `<unk>`.
  List<int> _word(String word) {
    final chars = word.runes.toList();
    final best = List<double>.filled(chars.length + 1, double.negativeInfinity)..[0] = 0;
    final from = List<int>.filled(chars.length + 1, 0);
    final piece = List<int>.filled(chars.length + 1, 0);
    for (var start = 0; start < chars.length; start++) {
      if (best[start] == double.negativeInfinity) continue;
      var known = false;
      for (var end = start + 1; end <= min(chars.length, start + _longest); end++) {
        final id = _ids[String.fromCharCodes(chars, start, end)];
        if (id == null) continue;
        if (end == start + 1) known = true;
        _relax(best, from, piece, start, end, id, _scores[id]);
      }
      if (!known) _relax(best, from, piece, start, start + 1, _unk, _unkScore);
    }
    final out = <int>[];
    for (var end = chars.length; end > 0; end = from[end]) {
      if (piece[end] == _unk && out.isNotEmpty && out.last == _unk) continue;
      out.add(piece[end]);
    }
    return out.reversed.toList();
  }

  static void _relax(
    List<double> best,
    List<int> from,
    List<int> piece,
    int start,
    int end,
    int id,
    double score,
  ) {
    if (best[start] + score <= best[end]) return;
    best[end] = best[start] + score;
    from[end] = start;
    piece[end] = id;
  }
}

/// multilingual-e5's sentence vector: the mean of the token states, at unit
/// length, so a dot product is the cosine. A message is a `query:`, a note a
/// `passage:`, as the model was trained.
class Embedder {
  Embedder(this.tokens, this.encode, {this.dim = 384});

  final List<int> Function(String text) tokens;
  final Encode encode;
  final int dim;

  Float32List query(String text) => _embed('query: $text');

  Float32List passage(String text) => _embed('passage: $text');

  Float32List _embed(String text) {
    final ids = tokens(text);
    final states = encode(ids);
    final mean = Float32List(dim);
    for (var t = 0; t < ids.length; t++) {
      for (var i = 0; i < dim; i++) {
        mean[i] += states[t * dim + i] / ids.length;
      }
    }
    final length = sqrt(mean.fold(0.0, (sum, x) => sum + x * x));
    for (var i = 0; i < dim; i++) {
      mean[i] /= length;
    }
    return mean;
  }
}

/// Gives every note without a current vector one, [batch] notes per call of
/// [embed], until none is left; returns how many it embedded.
Future<int> embedPending(
  NoteIndex index,
  Future<List<Float32List>> Function(List<String> texts) embed, {
  int batch = 16,
}) async {
  var done = 0;
  for (var notes = index.unembedded(batch); notes.isNotEmpty; notes = index.unembedded(batch)) {
    final vectors = await embed([for (final n in notes) n.text]);
    for (var i = 0; i < notes.length; i++) {
      index.storeVector(notes[i].path, notes[i].hash, vectors[i]);
    }
    done += notes.length;
  }
  return done;
}
