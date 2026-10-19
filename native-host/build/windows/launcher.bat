@echo off
REM AutoTISS2FA - Windows launcher (AutoFactorAuthenticator)
REM Installs/uninstalls the native messaging host for Firefox.

setlocal enabledelayedexpansion

set "APPDIR=%~dp0"
set "BINARY_PATH=%APPDIR%autotiss2fa-native.exe"
set "HOST_NAME=com.autofactor.autotiss2fa"
set "MANIFEST_DIR=%APPDATA%\Mozilla\NativeMessagingHosts"
set "MANIFEST_FILE=%MANIFEST_DIR%\com.autofactor.autotiss2fa.json"

REM --- Uninstall mode ---
if "%~1"=="--uninstall" (
    echo Uninstalling AutoTISS2FA...
    if exist "%MANIFEST_FILE%" del "%MANIFEST_FILE%"
    reg delete "HKCU\Software\Mozilla\NativeMessagingHosts\%HOST_NAME%" /f >nul 2>&1
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
    echo AutoTISS2FA is already installed.
    echo.
    set /p "CHOICE=Do you want to uninstall? (Y/N): "
    if /i "!CHOICE!"=="Y" (
        echo Uninstalling...
        del "%MANIFEST_FILE%"
        reg delete "HKCU\Software\Mozilla\NativeMessagingHosts\!HOST_NAME!" /f >nul 2>&1
        "%BINARY_PATH%" --delete-credential 2>nul
        echo Uninstall complete.
    ) else (
        echo AutoTISS2FA is ready to use.
    )
) else (
    echo AutoTISS2FA needs to register with Firefox.
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
        REM THE WINDOWS BUG FIXED IN 1.2: the manifest JSON path used to carry
        REM raw backslashes ("C:\Program Files\..."), which is an INVALID JSON
        REM escape, so Firefox could not parse the file and the extension never
        REM saw the host. JSON paths must use forward slashes.
        (
            echo {
            echo   "name": "%HOST_NAME%",
            echo   "description": "Native host for AutoTISS2FA",
            echo   "path": "!BINARY_PATH:\=/!",
            echo   "type": "stdio",
            echo   "allowed_extensions": ["autotiss2fa@autofactorauthenticator"]
            echo }
        ) > "%MANIFEST_FILE%"
        REM Firefox reads the default value of this registry key as the path to
        REM the manifest JSON file (not the binary itself).
        reg add "HKCU\Software\Mozilla\NativeMessagingHosts\%HOST_NAME%" /ve /d "%MANIFEST_FILE%" /f >nul
        echo.
        echo Installation complete!
        echo AutoTISS2FA is now ready to use with Firefox.
    ) else (
        echo Installation cancelled.
    )
)

pause
