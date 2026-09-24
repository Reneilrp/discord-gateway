@echo off
:: ==============================================================================
:: windows-power-settings.bat
:: ------------------------------------------------------------------------------
:: Run as Administrator in Command Prompt or PowerShell on Windows 11.
:: Prevents your laptop from sleeping or disconnecting Wi-Fi/Ethernet when
:: operating as a 24/7 self-hosted gateway server.
:: ==============================================================================

echo [Configuring Windows 11 Power Settings for Server Operation...]

:: 1. Set Lid Close Action to "Do Nothing" (0 = Do nothing, 1 = Sleep, 2 = Hibernate, 3 = Shut down)
:: Plugged in (AC)
powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
:: On Battery (DC)
powercfg /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
echo [OK] Closing the laptop lid will now NOT put the laptop to sleep.

:: 2. Set Sleep Timeout to NEVER when plugged in
powercfg /change standby-timeout-ac 0
echo [OK] Laptop sleep timeout when plugged in set to NEVER.

:: 3. Set Display Turn Off to 10 minutes (saves screen and heat while keeping CPU alive)
powercfg /change monitor-timeout-ac 10
echo [OK] Screen display will turn off after 10 minutes to save power and heat.

:: Apply the changes immediately
powercfg /setactive SCHEME_CURRENT

echo.
echo ==============================================================================
echo [SUCCESS] Windows 11 power policies updated!
echo You can now close your laptop lid and keep your gateway running 24/7.
echo.
echo IMPORTANT REMINDER:
echo In Device Manager -> Network Adapters -> Your Wi-Fi or Ethernet:
echo Right-click Properties -> Power Management -> UNCHECK:
echo "Allow the computer to turn off this device to save power"
echo ==============================================================================
pause
