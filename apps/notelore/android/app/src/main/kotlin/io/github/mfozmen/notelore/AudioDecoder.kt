package io.github.mfozmen.notelore

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteOrder

/**
 * An attached audio file as mono 16-bit PCM at its own rate (#285), for Whisper
 * after audio_native.dart resamples it to 16 kHz. Uses the platform's codecs
 * (AAC/M4A, MP3, Ogg, FLAC, …); throws when the file holds no audio it can read.
 */
object AudioDecoder {
    fun decode(file: File): Pair<ByteArray, Int> {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(file.path)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: throw IllegalArgumentException("no audio track")
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            val codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            codec.configure(format, null, null, 0)
            codec.start()
            try {
                return drain(extractor, codec, format)
            } finally {
                codec.stop()
                codec.release()
            }
        } finally {
            extractor.release()
        }
    }

    private fun drain(extractor: MediaExtractor, codec: MediaCodec, format: MediaFormat): Pair<ByteArray, Int> {
        var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        var float = false
        val out = ByteArrayOutputStream()
        val info = MediaCodec.BufferInfo()
        var inputDone = false
        while (true) {
            if (!inputDone) {
                val index = codec.dequeueInputBuffer(10_000)
                if (index >= 0) {
                    val size = extractor.readSampleData(codec.getInputBuffer(index)!!, 0)
                    if (size < 0) {
                        codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                    } else {
                        codec.queueInputBuffer(index, 0, size, extractor.sampleTime, 0)
                        extractor.advance()
                    }
                }
            }
            val index = codec.dequeueOutputBuffer(info, 10_000)
            if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                rate = codec.outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                channels = codec.outputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                // Some codecs hand back float samples rather than 16-bit ones.
                float = codec.outputFormat.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                    codec.outputFormat.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
            } else if (index >= 0) {
                val buffer = codec.getOutputBuffer(index)!!.order(ByteOrder.LITTLE_ENDIAN)
                // Mixed down to mono, frame by frame, as 16-bit.
                if (float) {
                    val floats = buffer.asFloatBuffer()
                    while (floats.remaining() >= channels) {
                        var sum = 0f
                        repeat(channels) { sum += floats.get() }
                        write(out, ((sum / channels).coerceIn(-1f, 1f) * 32767).toInt())
                    }
                } else {
                    val shorts = buffer.asShortBuffer()
                    while (shorts.remaining() >= channels) {
                        var sum = 0
                        repeat(channels) { sum += shorts.get() }
                        write(out, sum / channels)
                    }
                }
                codec.releaseOutputBuffer(index, false)
                // Longer than Whisper should sit through on a phone: refused, not decoded on.
                if (out.size() > MAX_SECONDS * rate * 2) throw IllegalArgumentException("too long")
                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
            }
        }
        return Pair(out.toByteArray(), rate)
    }

    private fun write(out: ByteArrayOutputStream, sample: Int) {
        out.write(sample and 0xFF)
        out.write((sample shr 8) and 0xFF)
    }

    /** Half an hour at most. */
    private const val MAX_SECONDS = 30 * 60
}
