@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION

SET APP_NAME=TA-Sysmon-Binary
SET LOG_FILE=%WINDIR%\sysmon_installer.log
SET LOCAL_SYSMON_EXE=%WINDIR%\sysmon.exe

CALL :log "INFO" "action='start_execution' script_name='deploy.bat' app_name='%APP_NAME%'"

CALL :get_splunk_path
IF NOT DEFINED SPLUNKPATH (
    CALL :log "ERROR" "action='find_splunk_path' status='fatal' message='SplunkForwarder path not found. Exiting.'"
    GOTO :EOF
)

SET VERSION_CONFIG_FILE="%SPLUNKPATH%\etc\apps\%APP_NAME%\default\sysmon_version.conf"
FOR /F "tokens=2 delims==" %%v IN ('type %VERSION_CONFIG_FILE% ^| find "version"') DO (
    SET TARGET_SYSMON_VERSION=%%v
)
SET TARGET_SYSMON_VERSION=!TARGET_SYSMON_VERSION: =!
CALL :log "INFO" "action='read_target_version' status='success' version='!TARGET_SYSMON_VERSION!'"

SET DEPLOY_BINARY_PATH="%SPLUNKPATH%\etc\apps\%APP_NAME%\bin\sysmon.exe"
SET DEPLOY_CONFIG_PATH="%SPLUNKPATH%\etc\apps\%APP_NAME%\bin\config.xml"

IF NOT EXIST %DEPLOY_BINARY_PATH% (
    CALL :log "WARN" "action='check_source_file' status='missing' message='sysmon.exe not found in package. Exiting.'"
    GOTO :cleanup
)

CALL :log "INFO" "action='copy_binary' status='starting'"
COPY /Y %DEPLOY_BINARY_PATH% %LOCAL_SYSMON_EXE% > NUL
IF %ERRORLEVEL% NEQ 0 (
    CALL :log "ERROR" "action='copy_binary' status='failed' error_code='%ERRORLEVEL%'. Exiting."
    GOTO :cleanup
)
CALL :log "INFO" "action='copy_binary' status='success'"

CALL :get_installed_version
IF NOT DEFINED INSTALLED_VERSION (
    CALL :log "INFO" "action='install_check' status='not_installed'. Proceeding with installation."
    GOTO :install_service
)

IF "!INSTALLED_VERSION!"=="!TARGET_SYSMON_VERSION!" (
    CALL :log "INFO" "action='version_compare' status='up_to_date'. No action needed."
    GOTO :cleanup
)

CALL :log "INFO" "action='version_compare' status='outdated' installed='!INSTALLED_VERSION!' target='!TARGET_SYSMON_VERSION!'. Proceeding with upgrade."
GOTO :upgrade_service

:install_service
CALL :log "INFO" "action='install_service' status='starting'"
%LOCAL_SYSMON_EXE% -accepteula -i %DEPLOY_CONFIG_PATH% > NUL
IF %ERRORLEVEL% NEQ 0 (
    CALL :log "ERROR" "action='install_service' status='failed' error_code='%ERRORLEVEL%'"
) ELSE (
    CALL :log "INFO" "action='install_service' status='success'"
)
GOTO :cleanup

:upgrade_service
CALL :log "INFO" "action='upgrade_service' status='starting'. Uninstalling old version first."
%LOCAL_SYSMON_EXE% -u force > NUL
CALL :log "INFO" "action='upgrade_service' status='uninstall_complete'. Installing new version."
%LOCAL_SYSMON_EXE% -accepteula -i %DEPLOY_CONFIG_PATH% > NUL
IF %ERRORLEVEL% NEQ 0 (
    CALL :log "ERROR" "action='upgrade_service' status='install_failed' error_code='%ERRORLEVEL%'"
) ELSE (
    CALL :log "INFO" "action='upgrade_service' status='success'"
)
GOTO :cleanup

:cleanup
CALL :log "INFO" "action='end_execution' script_name='deploy.bat' status='finished'"
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

:get_installed_version
SET ESCAPED_LOCAL_SYSMON_EXE=%WINDIR%\\sysmon.exe
SET INSTALLED_VERSION=
SET VERSION_METHOD="N/A"
IF NOT EXIST %LOCAL_SYSMON_EXE% ( GOTO :EOF )
FOR /F "tokens=2 delims==" %%v IN ('wmic datafile where name^="%ESCAPED_LOCAL_SYSMON_EXE%" get Version /value 2^>NUL ^| find "Version"') DO (SET INSTALLED_VERSION=%%v)
IF DEFINED INSTALLED_VERSION (
    SET VERSION_METHOD="WMI"
) ELSE (
    FOR /F "tokens=4" %%v IN ('%LOCAL_SYSMON_EXE% -nobanner 2^>NUL') DO (SET INSTALLED_VERSION=%%v)
    IF DEFINED INSTALLED_VERSION (
        SET INSTALLED_VERSION=!INSTALLED_VERSION:v=!
        SET VERSION_METHOD="Executable Output"
    )
)
IF DEFINED INSTALLED_VERSION (CALL :log "INFO" "action='get_version' status='success' method='%VERSION_METHOD%' version='!INSTALLED_VERSION!'")
GOTO :EOF

:log
ECHO timestamp="%DATE% %TIME%" level="%~1" %~2 >> %LOG_FILE%
GOTO :EOF

ENDLOCAL
