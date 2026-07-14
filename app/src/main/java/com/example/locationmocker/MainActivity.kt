package com.example.locationmocker

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.graphics.Color
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.locationmocker.data.SettingsRepository
import com.example.locationmocker.presentation.MainScreen
import com.example.locationmocker.presentation.MainViewModel
import com.example.locationmocker.presentation.MainViewModelFactory

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
            val colorScheme = if (isSystemInDarkTheme()) {
                darkColorScheme(
                    primary = Color(0xFF74D9C5),
                    onPrimary = Color(0xFF00382F),
                    primaryContainer = Color(0xFF005045),
                    onPrimaryContainer = Color(0xFF94F7E0),
                    secondary = Color(0xFFA8CDDB),
                    secondaryContainer = Color(0xFF294A56),
                    surface = Color(0xFF101513),
                    surfaceVariant = Color(0xFF3F4945),
                )
            } else {
                lightColorScheme(
                    primary = Color(0xFF006B5C),
                    onPrimary = Color.White,
                    primaryContainer = Color(0xFF9EF2DC),
                    onPrimaryContainer = Color(0xFF00201A),
                    secondary = Color(0xFF486A73),
                    secondaryContainer = Color(0xFFCBE8F0),
                    tertiary = Color(0xFF765A00),
                    surface = Color(0xFFF8FBF9),
                    surfaceVariant = Color(0xFFDBE5E1),
                    background = Color(0xFFF5FAF7),
                )
            }
            MaterialTheme(colorScheme = colorScheme) {
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
