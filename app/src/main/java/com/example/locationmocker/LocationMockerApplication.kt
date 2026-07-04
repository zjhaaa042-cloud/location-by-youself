package com.example.locationmocker

import android.app.Application
import com.amap.api.maps.MapsInitializer

class LocationMockerApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        MapsInitializer.updatePrivacyShow(this, true, true)
        MapsInitializer.updatePrivacyAgree(this, true)
    }
}
