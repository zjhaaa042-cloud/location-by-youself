package com.example.locationmocker.domain.route

import com.example.locationmocker.domain.model.PlaybackMode
import com.example.locationmocker.domain.model.RouteSample

class PlaybackCursor(
    private val samples: List<RouteSample>,
    private val mode: PlaybackMode,
) {
    private var index = 0
    private var direction = 1
    private var completed = false

    fun next(): RouteSample? {
        if (samples.isEmpty() || completed) return null
        if (samples.size == 1) {
            if (mode == PlaybackMode.Once) completed = true
            return samples.first()
        }

        val current = samples[index]
        advance()
        return current
    }

    private fun advance() {
        when (mode) {
            PlaybackMode.Once -> {
                if (index >= samples.lastIndex) {
                    completed = true
                } else {
                    index++
                }
            }

            PlaybackMode.Loop -> {
                index = if (index >= samples.lastIndex) 0 else index + 1
            }

            PlaybackMode.PingPong -> {
                val nextIndex = index + direction
                when {
                    nextIndex > samples.lastIndex -> {
                        direction = -1
                        index = samples.lastIndex - 1
                    }

                    nextIndex < 0 -> {
                        direction = 1
                        index = 1
                    }

                    else -> index = nextIndex
                }
            }
        }
    }
}
