@echo off
REM TU Wien 2FA — Windows launcher
REM Installs/uninstalls the native messaging host for Firefox.

setlocal enabledelayedexpansion

set "APPDIR=%~dp0"
set "BINARY_PATH=%APPDIR%tuwien-2fa-native.exe"
set "MANIFEST_DIR=%APPDATA%\Mozilla\NativeMessagingHosts"
set "MANIFEST_FILE=%MANIFEST_DIR%\com.tuwien.2fa.json"

REM --- Uninstall mode ---
if "%~1"=="--uninstall" (
    echo Uninstalling TU Wien 2FA...
    if exist "%MANIFEST_FILE%" del "%MANIFEST_FILE%"
    if exist "%BINARY_PATH%" "%BINARY_PATH%" --delete-credential 2>nul
    echo Uninstall complete.
    pause
    exit /b 0
)

REM --- Normal launch ---
if not exist "%BINARY_PATH%" (
    echo Error: Native host binary not found.
    pause
    exit /b 1
)

if exist "%MANIFEST_FILE%" (
    echo TU Wien 2FA is already installed.
    echo.
    set /p "CHOICE=Do you want to uninstall? (Y/N): "
    if /i "!CHOICE!"=="Y" (
        echo Uninstalling...
        del "%MANIFEST_FILE%"
        "%BINARY_PATH%" --delete-credential 2>nul
        echo Uninstall complete.
    ) else (
        echo TU Wien 2FA is ready to use.
    )
) else (
    echo TU Wien 2FA needs to register with Firefox.
    echo.
    echo This will create a configuration file so the extension can communicate
    echo with the native host.
    echo.
    echo No personal data is stored. Your TOTP seed will be saved securely in
    echo Windows Credential Manager when you configure it in the extension.
    echo.
    set /p "CHOICE=Do you want to proceed? (Y/N): "
    if /i "!CHOICE!"=="Y" (
        if not exist "%MANIFEST_DIR%" mkdir "%MANIFEST_DIR%"
        (
            echo {
            echo   "name": "com.tuwien.2fa",
            echo   "description": "Native host for TU Wien Auto 2FA",
            echo   "path": "%BINARY_PATH%",
            echo   "type": "stdio",
            echo   "allowed_extensions": ["tuwien-auto-2fa@aGreatTUWienStudent"]
            echo }
        ) > "%MANIFEST_FILE%"
        echo.
        echo Installation complete!
        echo TU Wien 2FA is now ready to use with Firefox.
    ) else (
        echo Installation cancelled.
    )
)

pause
