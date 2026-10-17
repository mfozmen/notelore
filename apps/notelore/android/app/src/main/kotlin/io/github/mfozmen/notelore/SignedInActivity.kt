package io.github.mfozmen.notelore

import android.app.Activity
import android.app.ActivityManager
import android.content.Intent
import android.os.Bundle

/**
 * Where the sign-in page sends the browser once it is done (notelore://signed-in, #301):
 * brings Notelore's own task to the front with MainActivity on top, which closes the
 * sign-in tab above it. The waiting sign-in then goes on (#300). Shows nothing itself.
 */
class SignedInActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val main = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val task = getSystemService(ActivityManager::class.java).appTasks.firstOrNull {
            it.taskInfo.baseActivity?.className == MainActivity::class.java.name
        }
        if (task != null) {
            task.moveToFront()
            task.startActivity(this, main, null)
        } else {
            startActivity(main.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) // the app was gone: start it
        }
        finish()
    }
}
