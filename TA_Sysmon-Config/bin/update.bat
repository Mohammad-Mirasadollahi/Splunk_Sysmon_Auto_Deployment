@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION

SET APP_NAME=TA-Sysmon-Config
SET LOG_FILE=%WINDIR%\sysmon_config_updater.log
SET LOCAL_SYSMON_EXE=%WINDIR%\sysmon.exe
SET LOCAL_CONFIG_FILE=%WINDIR%\config.xml

CALL :log "INFO" "action='start_execution' script_name='update.bat' app_name='%APP_NAME%'"

IF NOT EXIST %LOCAL_SYSMON_EXE% (
    CALL :log "WARN" "action='dependency_check' status='failed' message='sysmon.exe not found. Waiting for TA-Sysmon-Binary to run. Exiting.'"
    GOTO :cleanup
)

sc query Sysmon | find "RUNNING" > NUL
IF %ERRORLEVEL% NEQ 0 (
    CALL :log "WARN" "action='dependency_check' status='failed' message='Sysmon service is not running. Waiting for TA-Sysmon-Binary to install/start service. Exiting.'"
    GOTO :cleanup
)

CALL :get_splunk_path
IF NOT DEFINED SPLUNKPATH (
    CALL :log "ERROR" "action='find_splunk_path' status='fatal' message='SplunkForwarder path not found. Exiting.'"
    GOTO :EOF
)

SET DEPLOY_CONFIG_PATH="%SPLUNKPATH%\etc\apps\%APP_NAME%\bin\config.xml"

CALL :log "INFO" "action='deploy_config' status='starting' message='Copying authoritative config file.'"
COPY /Y %DEPLOY_CONFIG_PATH% %LOCAL_CONFIG_FILE% > NUL
IF %ERRORLEVEL% NEQ 0 (
    CALL :log "ERROR" "action='deploy_config' status='failed' error_code='%ERRORLEVEL%'. Exiting."
    GOTO :cleanup
)
CALL :log "INFO" "action='deploy_config' status='success' message='Authoritative config file copied to system.'"

CALL :log "INFO" "action='update_config' status='starting'"
%LOCAL_SYSMON_EXE% -c %LOCAL_CONFIG_FILE% > NUL
IF %ERRORLEVEL% NEQ 0 (
    CALL :log "ERROR" "action='update_config' status='failed' error_code='%ERRORLEVEL%'"
) ELSE (
    CALL :log "INFO" "action='update_config' status='success' message='Sysmon configuration applied successfully.'"
)
GOTO :cleanup

:cleanup
CALL :log "INFO" "action='end_execution' script_name='update.bat' status='finished'"
GOTO :EOF

:get_splunk_path
SET SPLUNK_PATH_METHOD="N/A"
FOR /F "tokens=1,2,*" %%a IN ('wmic service SplunkForwarder get PathName /value ^| find "PathName"') DO (SET SPLUNKDPATH=%%c)
IF DEFINED SPLUNKDPATH (
    SET SPLUNKPATH=!SPLUNKDPATH:"=!
    SET SPLUNKPATH=!SPLUNKPATH:~0,-28!
    SET SPLUNK_PATH_METHOD="WMI"
) ELSE (
    FOR /F "tokens=2*" %%a IN ('reg query "HKLM\SOFTWARE\Splunk\SplunkUniversalForwarder" /v InstallPath 2^>NUL ^| find "InstallPath"') DO (SET SPLUNKPATH=%%b)
    IF DEFINED SPLUNKPATH (SET SPLUNK_PATH_METHOD="Registry")
)
IF DEFINED SPLUNKPATH (CALL :log "INFO" "action='find_splunk_path' status='success' method='%SPLUNK_PATH_METHOD%' path='%SPLUNKPATH%'")
GOTO :EOF

:log
ECHO timestamp="%DATE% %TIME%" level="%~1" %~2 >> %LOG_FILE%
GOTO :EOF

ENDLOCAL
