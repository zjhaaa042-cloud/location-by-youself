package com.example.locationmocker

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.locationmocker.data.SettingsRepository
import com.example.locationmocker.presentation.MainScreen
import com.example.locationmocker.presentation.MainViewModel
import com.example.locationmocker.presentation.MainViewModelFactory
import com.example.locationmocker.presentation.ui.theme.LocationMockerTheme

class MainActivity : ComponentActivity() {
    private var activeViewModel: MainViewModel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val permissionLauncher = registerForActivityResult(
            ActivityResultContracts.RequestMultiplePermissions(),
        ) {
            activeViewModel?.refreshReadiness()
        }

        setContent {
            LocationMockerTheme {
                val factory = remember {
                    MainViewModelFactory(
                        application = application,
                        settingsRepository = SettingsRepository(applicationContext),
                    )
                }
                val viewModel: MainViewModel = viewModel(factory = factory)
                activeViewModel = viewModel

                LaunchedEffect(Unit) {
                    val permissions = buildList {
                        add(Manifest.permission.ACCESS_FINE_LOCATION)
                        add(Manifest.permission.ACCESS_COARSE_LOCATION)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            add(Manifest.permission.POST_NOTIFICATIONS)
                        }
                    }.toTypedArray()
                    permissionLauncher.launch(permissions)
                }

                MainScreen(
                    viewModel = viewModel,
                    onRequestPermissions = {
                        val permissions = buildList {
                            add(Manifest.permission.ACCESS_FINE_LOCATION)
                            add(Manifest.permission.ACCESS_COARSE_LOCATION)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                add(Manifest.permission.POST_NOTIFICATIONS)
                            }
                        }.toTypedArray()
                        permissionLauncher.launch(permissions)
                    },
                )
            }
        }
    }

    override fun onResume() {
        super.onResume()
        activeViewModel?.refreshReadiness()
    }
}
