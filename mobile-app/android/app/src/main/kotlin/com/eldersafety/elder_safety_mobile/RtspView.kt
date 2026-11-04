package com.eldersafety.elder_safety_mobile

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.View
import android.graphics.Color
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.videolan.libvlc.LibVLC
import org.videolan.libvlc.Media
import org.videolan.libvlc.MediaPlayer
import org.videolan.libvlc.util.VLCVideoLayout

class RtspViewFactory(private val messenger: BinaryMessenger) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        RtspView(context, viewId, messenger, (args as? Map<*, *>)?.get("url") as? String ?: "")
}

private class RtspView(context: Context, id: Int, messenger: BinaryMessenger, url: String) : PlatformView {
    private val layout = VLCVideoLayout(context)
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "anju/rtsp/$id")
    private var engine: LibVLC? = null
    private var player: MediaPlayer? = null
    private var disposed = false
    init {
        layout.setBackgroundColor(Color.BLACK)
        try {
            // Keep native RTSP playback isolated from Flutter texture/seek state.
            // This view never accepts script commands, public endpoints or logs credentials.
            val uri = Uri.parse(url)
            val parts = (uri.host ?: "").split('.').mapNotNull { it.toIntOrNull() }
            val privateHost = parts.size == 4 && parts.all { it in 0..255 } &&
                (parts[0] == 10 || (parts[0] == 192 && parts[1] == 168) ||
                    (parts[0] == 172 && parts[1] in 16..31))
            require(uri.scheme == "rtsp" && privateHost)
            val vlc = LibVLC(context.applicationContext, arrayListOf("--quiet", "--rtsp-tcp", "--no-audio", "--no-video-title-show"))
            engine = vlc
            val p = MediaPlayer(vlc)
            player = p
            p.setEventListener { event ->
                when (event.type) {
                    MediaPlayer.Event.Playing -> status("playing")
                    MediaPlayer.Event.Buffering -> if (event.buffering < 100) status("buffering")
                    MediaPlayer.Event.EncounteredError -> status("error")
                    MediaPlayer.Event.EndReached -> status("ended")
                }
            }
            p.attachViews(layout, null, false, true)
            val media = Media(vlc, uri)
            // Software decode works with H.264/H.265 on devices lacking a matching hardware decoder.
            media.setHWDecoderEnabled(false, false)
            media.addOption(":rtsp-tcp")
            media.addOption(":network-caching=500")
            p.media = media
            media.release()
            // Start after Android has attached the native SurfaceView to Flutter's hierarchy.
            layout.post { if (!disposed) p.play() }
        } catch (_: Exception) {
            layout.post { status("error") }
        }
    }
    private fun status(value: String) {
        main.post { if (!disposed) channel.invokeMethod("status", value) }
    }
    override fun getView(): View = layout
    override fun dispose() {
        if (disposed) return
        disposed = true
        main.removeCallbacksAndMessages(null)
        player?.let { p ->
            p.setEventListener(null)
            p.stop()
            p.detachViews()
            p.release()
        }
        player = null
        engine?.release()
        engine = null
    }
}
