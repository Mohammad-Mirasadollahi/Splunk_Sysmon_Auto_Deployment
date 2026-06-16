@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION

REM --- ======================================================================
REM --- Configuration
REM --- ======================================================================
SET "SERVICE_NAME=Sysmon"
SET "TARGET_DIR=%WINDIR%\Sysmon"
SET "LOG_FILE=%TARGET_DIR%\sysmon_installer.log"
SET "TEMP_OUTPUT_FILE=%TEMP%\sysmon_version_check.tmp"

SET "SCRIPT_DIR=%~dp0"
SET "LOCAL_SYSMON_EXE=%SCRIPT_DIR%Sysmon.exe"

SET "ADDON_ROOT_DIR=%SCRIPT_DIR%..\"
SET "LOCAL_CONF_FILE=%ADDON_ROOT_DIR%local\sysmon.xml"
SET "DEFAULT_CONF_FILE=%ADDON_ROOT_DIR%default\sysmon.xml"

SET "INSTALLED_SYSMON_EXE=%TARGET_DIR%\Sysmon.exe"
SET "FINAL_CONFIG_FILE=%TARGET_DIR%\config.xml"

REM --- ======================================================================
REM --- Script Execution Start
REM --- ======================================================================
IF NOT EXIST "%TARGET_DIR%" MKDIR "%TARGET_DIR%"
CALL :log "INFO" "action='start_execution' script_name='deploy.bat'"

IF NOT EXIST "%LOCAL_SYSMON_EXE%" (
    CALL :log "ERROR" "action='check_local_file' status='fatal' message='Sysmon.exe not found in the bin folder next to the script.'"
    GOTO :EOF
)

sc query "!SERVICE_NAME!" >nul 2>&1
IF %ERRORLEVEL% EQU 0 CALL :get_installed_version

CALL :prepare_environment
IF %ERRORLEVEL% NEQ 0 GOTO :cleanup

CALL :get_target_version
IF NOT DEFINED TARGET_SYSMON_VERSION (
    CALL :log "ERROR" "action='read_target_version' status='failed' message='Could not determine version from local Sysmon.exe.'"
    GOTO :cleanup
)

IF NOT DEFINED INSTALLED_VERSION (
    CALL :log "INFO" "action='install_check' status='not_installed'. Proceeding with first-time installation."
    GOTO :first_time_install
)

IF "!INSTALLED_VERSION!"=="!TARGET_SYSMON_VERSION!" (
    CALL :log "INFO" "action='version_compare' status='up_to_date'. No action needed."
    CALL :verify_service_status
    GOTO :cleanup
)

CALL :log "INFO" "action='version_compare' status='outdated' installed='!INSTALLED_VERSION!' target='!TARGET_SYSMON_VERSION!'. Proceeding with upgrade."
GOTO :upgrade_service

REM --- ======================================================================
REM --- Action Blocks
REM --- ======================================================================
:first_time_install
    CALL :log "INFO" "action='first_time_install' status='starting'"
    CALL :install_service
    CALL :verify_service_status
    GOTO :cleanup

:upgrade_service
    CALL :log "INFO" "action='upgrade_service' status='starting'"
    CALL :uninstall_service
    CALL :force_kill_process
    CALL :install_service
    CALL :verify_service_status
    GOTO :cleanup

:cleanup
    IF EXIST "%TEMP_OUTPUT_FILE%" DEL "%TEMP_OUTPUT_FILE%"
    CALL :log "INFO" "action='end_execution' script_name='deploy.bat' status='finished'"
    GOTO :EOF

REM --- ======================================================================
REM --- Subroutines
REM --- ======================================================================
:prepare_environment
    CALL :log "INFO" "action='prepare_environment' status='starting'"

    COPY /Y "%LOCAL_SYSMON_EXE%" "%INSTALLED_SYSMON_EXE%" > NUL
    IF %ERRORLEVEL% NEQ 0 (
        CALL :log "ERROR" "action='copy_executable' status='failed' error_code='%ERRORLEVEL%'"
        EXIT /B 1
    )

    REM --- BULLETPROOF LOGIC: Using GOTO instead of IF/ELSE to avoid CMD bugs
    IF EXIST "%LOCAL_CONF_FILE%" GOTO :use_local_config
    IF EXIST "%DEFAULT_CONF_FILE%" GOTO :use_default_config
    GOTO :no_config_found

:use_local_config
    CALL :log "INFO" "action='config_check' status='found_local' message='Using local config file from %LOCAL_CONF_FILE%'"
    COPY /Y "%LOCAL_CONF_FILE%" "%FINAL_CONFIG_FILE%" > NUL
    GOTO :verify_config_copy

:use_default_config
    CALL :log "INFO" "action='config_check' status='found_default' message='Using default config file from %DEFAULT_CONF_FILE%'"
    COPY /Y "%DEFAULT_CONF_FILE%" "%FINAL_CONFIG_FILE%" > NUL
    GOTO :verify_config_copy

:no_config_found
    CALL :log "ERROR" "action='config_check' status='fatal' message='No valid XML config file found in local or default directories. Cannot proceed.'"
    EXIT /B 1

:verify_config_copy
    IF %ERRORLEVEL% NEQ 0 (
        CALL :log "ERROR" "action='copy_config' status='failed' error_code='%ERRORLEVEL%'"
        EXIT /B 1
    )
    EXIT /B 0

:install_service
    CALL :log "INFO" "action='install_service' status='starting' config_path='%FINAL_CONFIG_FILE%'"
    "%INSTALLED_SYSMON_EXE%" -accepteula -i "%FINAL_CONFIG_FILE%" > NUL
    IF %ERRORLEVEL% NEQ 0 (
        CALL :log "ERROR" "action='install_service' status='failed' error_code='%ERRORLEVEL%'"
    ) ELSE (
        CALL :log "INFO" "action='install_service' status='success'"
    )
    GOTO :EOF

:uninstall_service
    CALL :log "INFO" "action='uninstall_service' status='starting'"
    IF NOT EXIST "%INSTALLED_SYSMON_EXE%" EXIT /B 0
    "%INSTALLED_SYSMON_EXE%" -u force > NUL
    IF %ERRORLEVEL% NEQ 0 (
        CALL :log "WARN" "action='uninstall_service' status='failed_or_not_installed' error_code='%ERRORLEVEL%'"
    ) ELSE (
        CALL :log "INFO" "action='uninstall_service' status='success'"
    )
    EXIT /B 0

:force_kill_process
    CALL :log "INFO" "action='force_kill_process' status='starting' process_name='sysmon.exe'"
    taskkill /F /IM sysmon.exe /T >nul 2>&1
    GOTO :EOF

:verify_service_status
    CALL :log "INFO" "action='verify_service_status' status='checking' service_name='!SERVICE_NAME!'"
    sc query "!SERVICE_NAME!" | find "STATE" | find "RUNNING" >nul
    IF %ERRORLEVEL% NEQ 0 (
        CALL :log "WARN" "action='verify_service_status' status='not_running' message='Attempting to start the service.'"
        net start "!SERVICE_NAME!" >nul
        IF %ERRORLEVEL% NEQ 0 (
            CALL :log "ERROR" "action='verify_service_status' status='start_failed' error_code='%ERRORLEVEL%'"
        ) ELSE (
            CALL :log "INFO" "action='verify_service_status' status='start_success'"
        )
    ) ELSE (
        CALL :log "INFO" "action='verify_service_status' status='already_running'"
    )
    GOTO :EOF

:get_target_version
    SET "TARGET_SYSMON_VERSION="
    "%LOCAL_SYSMON_EXE%" -accepteula > "%TEMP_OUTPUT_FILE%" 2>&1
    IF NOT EXIST "%TEMP_OUTPUT_FILE%" GOTO :EOF
    FOR /F "tokens=3" %%v IN ('findstr /B "System Monitor" "%TEMP_OUTPUT_FILE%"') DO SET "TARGET_SYSMON_VERSION=%%v"
    IF DEFINED TARGET_SYSMON_VERSION (
        SET "TARGET_SYSMON_VERSION=!TARGET_SYSMON_VERSION:v=!"
        CALL :log "INFO" "action='get_target_version' status='success' version='!TARGET_SYSMON_VERSION!'"
    )
    GOTO :EOF

:get_installed_version
    SET "INSTALLED_VERSION="
    IF NOT EXIST "%INSTALLED_SYSMON_EXE%" GOTO :EOF
    "%INSTALLED_SYSMON_EXE%" -accepteula > "%TEMP_OUTPUT_FILE%" 2>&1
    IF NOT EXIST "%TEMP_OUTPUT_FILE%" GOTO :EOF
    FOR /F "tokens=3" %%v IN ('findstr /B "System Monitor" "%TEMP_OUTPUT_FILE%"') DO SET "INSTALLED_VERSION=%%v"
    IF DEFINED INSTALLED_VERSION (
        SET "INSTALLED_VERSION=!INSTALLED_VERSION:v=!"
        CALL :log "INFO" "action='get_installed_version' status='success' version='!INSTALLED_VERSION!'"
    ) ELSE (
        CALL :log "WARN" "action='get_installed_version' status='read_failed'"
    )
    GOTO :EOF

:log
    ECHO timestamp="%DATE% %TIME%" level="%~1" %~2 >> "%LOG_FILE%"
    GOTO :EOF

ENDLOCAL
