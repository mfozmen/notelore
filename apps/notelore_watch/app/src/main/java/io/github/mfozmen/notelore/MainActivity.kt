package io.github.mfozmen.notelore

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.speech.RecognizerIntent
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.Wearable
import org.json.JSONObject

/// A note spoken into the watch: the phone runs the turn, the answer comes
/// back through the Wearable Data Layer (#823). Queued while the phone is away.
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                val activity = this
                var entries by remember { mutableStateOf(WatchStore.queue(activity).entries) }
                fun refresh() {
                    entries = WatchStore.queue(activity).entries
                }
                fun send(text: String) {
                    val clean = text.trim()
                    if (clean.isEmpty()) return
                    val entry = WatchStore.queue(activity).add(clean)
                    WatchStore.send(activity, entry)
                    refresh()
                }
                DisposableEffect(Unit) {
                    val listener = MessageClient.OnMessageReceivedListener { event ->
                        if (event.path == "/notelore/answer") {
                            runCatching { JSONObject(String(event.data)) }.getOrNull()?.let { payload ->
                                WatchStore.queue(activity)
                                    .answer(payload.optString("id"), payload.optString("answer"))
                                runOnUiThread { refresh() }
                            }
                        }
                    }
                    Wearable.getMessageClient(activity).addListener(listener)
                    onDispose { Wearable.getMessageClient(activity).removeListener(listener) }
                }
                val speech = rememberLauncherForActivityResult(
                    ActivityResultContracts.StartActivityForResult(),
                ) { result ->
                    if (result.resultCode == Activity.RESULT_OK) {
                        val said = result.data
                            ?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                            ?.firstOrNull()
                        if (!said.isNullOrBlank()) send(said)
                    }
                }
                Scaffold(timeText = { TimeText() }) {
                    ScalingLazyColumn(modifier = Modifier.fillMaxSize()) {
                        item {
                            Chip(
                                label = { Text("Speak") },
                                onClick = {
                                    val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                                        .putExtra(
                                            RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                                            RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
                                        )
                                    runCatching { speech.launch(intent) }
                                },
                            )
                        }
                        item { TypeRow(onSend = ::send) }
                        items(entries) { entry ->
                            Column(
                                modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                                verticalArrangement = Arrangement.spacedBy(2.dp),
                            ) {
                                Text(entry.text)
                                if (entry.answer == null) {
                                    CircularProgressIndicator(
                                        modifier = Modifier.size(16.dp),
                                        strokeWidth = 2.dp,
                                    )
                                } else {
                                    Text(
                                        entry.answer,
                                        color = MaterialTheme.colors.primary,
                                        fontSize = 12.sp,
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@androidx.compose.runtime.Composable
private fun TypeRow(onSend: (String) -> Unit) {
    var text by remember { mutableStateOf("") }
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        BasicTextField(
            value = text,
            onValueChange = { text = it },
            modifier = Modifier.weight(1f),
            textStyle = TextStyle(color = Color.White, fontSize = 14.sp),
        )
        Chip(
            label = { Text("Send") },
            onClick = {
                onSend(text)
                text = ""
            },
        )
    }
}
