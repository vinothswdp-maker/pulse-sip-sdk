package com.pulse.sampleapp

import android.app.Application
import com.pulse.sipsdk.PulseSipSdk

/** Mirrors exactly what a real customer's Application class would do. */
class SampleApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        PulseSipSdk.initialize(this)
    }
}
