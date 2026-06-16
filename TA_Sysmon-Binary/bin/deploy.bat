@ECHO OFF
SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION

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

SET "SOURCE_CONFIG_FILE="
SET "TARGET_SYSMON_VERSION="
SET "INSTALLED_VERSION="

REM --- ======================================================================
REM --- Entry point
REM --- The decision logic lives in :main so every branch can return with
REM --- EXIT /B. This avoids using GOTO inside parenthesized IF blocks, which
REM --- is a well-known source of CMD parser bugs.
REM --- ======================================================================
CALL :main
CALL :cleanup
ENDLOCAL
GOTO :EOF

:main
    IF NOT EXIST "%TARGET_DIR%" MKDIR "%TARGET_DIR%"
    CALL :log "INFO" "action='start_execution' script_name='deploy.bat'"

    IF NOT EXIST "%LOCAL_SYSMON_EXE%" (
        CALL :log "ERROR" "action='check_local_file' status='fatal' message='Sysmon.exe not found in the bin folder next to the script.'"
        EXIT /B 1
    )

    CALL :resolve_source_config
    IF NOT DEFINED SOURCE_CONFIG_FILE EXIT /B 1

    CALL :get_target_version
    IF NOT DEFINED TARGET_SYSMON_VERSION (
        CALL :log "ERROR" "action='read_target_version' status='failed' message='Could not determine version from local Sysmon.exe.'"
        EXIT /B 1
    )

    sc query "%SERVICE_NAME%" >NUL 2>&1
    IF NOT ERRORLEVEL 1 CALL :get_installed_version

    IF NOT DEFINED INSTALLED_VERSION (
        CALL :log "INFO" "action='decision' status='not_installed' message='Proceeding with first-time installation.'"
        CALL :install_fresh
        EXIT /B 0
    )

    IF "!INSTALLED_VERSION!"=="!TARGET_SYSMON_VERSION!" (
        CALL :log "INFO" "action='decision' status='up_to_date' version='!INSTALLED_VERSION!'"
        CALL :refresh_config
        CALL :verify_service_status
        EXIT /B 0
    )

    CALL :log "INFO" "action='decision' status='outdated' installed='!INSTALLED_VERSION!' target='!TARGET_SYSMON_VERSION!'"
    CALL :upgrade_service
    EXIT /B 0

REM --- ======================================================================
REM --- Action blocks
REM --- ======================================================================
:install_fresh
    CALL :log "INFO" "action='first_time_install' status='starting'"
    CALL :deploy_exe
    IF ERRORLEVEL 1 EXIT /B 1
    CALL :deploy_config
    IF ERRORLEVEL 1 EXIT /B 1
    CALL :install_service
    CALL :verify_service_status
    EXIT /B 0

:upgrade_service
    CALL :log "INFO" "action='upgrade_service' status='starting'"
    REM Uninstall and kill first so the running Sysmon.exe is no longer locked
    REM before we overwrite it with the new binary.
    CALL :uninstall_service
    CALL :force_kill_process
    CALL :deploy_exe
    IF ERRORLEVEL 1 EXIT /B 1
    CALL :deploy_config
    IF ERRORLEVEL 1 EXIT /B 1
    CALL :install_service
    CALL :verify_service_status
    EXIT /B 0

:refresh_config
    REM Same version already installed: just push the latest config to the
    REM running service instead of reinstalling it.
    CALL :deploy_config
    IF ERRORLEVEL 1 EXIT /B 1
    CALL :log "INFO" "action='refresh_config' status='applying'"
    "%INSTALLED_SYSMON_EXE%" -c "%FINAL_CONFIG_FILE%" >NUL 2>&1
    IF ERRORLEVEL 1 (
        CALL :log "WARN" "action='refresh_config' status='failed' error_code='!ERRORLEVEL!'"
    ) ELSE (
        CALL :log "INFO" "action='refresh_config' status='success'"
    )
    EXIT /B 0

:cleanup
    IF EXIST "%TEMP_OUTPUT_FILE%" DEL "%TEMP_OUTPUT_FILE%"
    CALL :log "INFO" "action='end_execution' script_name='deploy.bat' status='finished'"
    EXIT /B 0

REM --- ======================================================================
REM --- Subroutines
REM --- ======================================================================
:resolve_source_config
    SET "SOURCE_CONFIG_FILE="
    IF EXIST "%LOCAL_CONF_FILE%" (
        SET "SOURCE_CONFIG_FILE=%LOCAL_CONF_FILE%"
        CALL :log "INFO" "action='config_check' status='found_local' path='%LOCAL_CONF_FILE%'"
        EXIT /B 0
    )
    IF EXIST "%DEFAULT_CONF_FILE%" (
        SET "SOURCE_CONFIG_FILE=%DEFAULT_CONF_FILE%"
        CALL :log "INFO" "action='config_check' status='found_default' path='%DEFAULT_CONF_FILE%'"
        EXIT /B 0
    )
    CALL :log "ERROR" "action='config_check' status='fatal' message='No valid XML config file found in local or default directories. Cannot proceed.'"
    EXIT /B 1

:deploy_exe
    COPY /Y "%LOCAL_SYSMON_EXE%" "%INSTALLED_SYSMON_EXE%" >NUL
    IF ERRORLEVEL 1 (
        CALL :log "ERROR" "action='deploy_exe' status='failed' error_code='!ERRORLEVEL!'"
        EXIT /B 1
    )
    CALL :log "INFO" "action='deploy_exe' status='success'"
    EXIT /B 0

:deploy_config
    COPY /Y "%SOURCE_CONFIG_FILE%" "%FINAL_CONFIG_FILE%" >NUL
    IF ERRORLEVEL 1 (
        CALL :log "ERROR" "action='deploy_config' status='failed' error_code='!ERRORLEVEL!'"
        EXIT /B 1
    )
    CALL :log "INFO" "action='deploy_config' status='success' source='!SOURCE_CONFIG_FILE!'"
    EXIT /B 0

:install_service
    CALL :log "INFO" "action='install_service' status='starting' config_path='%FINAL_CONFIG_FILE%'"
    "%INSTALLED_SYSMON_EXE%" -accepteula -i "%FINAL_CONFIG_FILE%" >NUL 2>&1
    IF ERRORLEVEL 1 (
        CALL :log "ERROR" "action='install_service' status='failed' error_code='!ERRORLEVEL!'"
        EXIT /B 1
    )
    CALL :log "INFO" "action='install_service' status='success'"
    EXIT /B 0

:uninstall_service
    CALL :log "INFO" "action='uninstall_service' status='starting'"
    IF NOT EXIST "%INSTALLED_SYSMON_EXE%" EXIT /B 0
    "%INSTALLED_SYSMON_EXE%" -u force >NUL 2>&1
    IF ERRORLEVEL 1 (
        CALL :log "WARN" "action='uninstall_service' status='failed_or_not_installed' error_code='!ERRORLEVEL!'"
    ) ELSE (
        CALL :log "INFO" "action='uninstall_service' status='success'"
    )
    EXIT /B 0

:force_kill_process
    CALL :log "INFO" "action='force_kill_process' status='starting' process_name='Sysmon.exe'"
    taskkill /F /IM Sysmon.exe /T >NUL 2>&1
    taskkill /F /IM Sysmon64.exe /T >NUL 2>&1
    EXIT /B 0

:verify_service_status
    CALL :log "INFO" "action='verify_service_status' status='checking' service_name='%SERVICE_NAME%'"
    sc query "%SERVICE_NAME%" | find "STATE" | find "RUNNING" >NUL
    IF NOT ERRORLEVEL 1 (
        CALL :log "INFO" "action='verify_service_status' status='already_running'"
        EXIT /B 0
    )
    CALL :log "WARN" "action='verify_service_status' status='not_running' message='Attempting to start the service.'"
    net start "%SERVICE_NAME%" >NUL 2>&1
    IF ERRORLEVEL 1 (
        CALL :log "ERROR" "action='verify_service_status' status='start_failed' error_code='!ERRORLEVEL!'"
        EXIT /B 1
    )
    CALL :log "INFO" "action='verify_service_status' status='start_success'"
    EXIT /B 0

:get_target_version
    SET "TARGET_SYSMON_VERSION="
    "%LOCAL_SYSMON_EXE%" -accepteula >"%TEMP_OUTPUT_FILE%" 2>&1
    IF NOT EXIST "%TEMP_OUTPUT_FILE%" EXIT /B 0
    FOR /F "tokens=3" %%v IN ('findstr /B "System Monitor" "%TEMP_OUTPUT_FILE%"') DO SET "TARGET_SYSMON_VERSION=%%v"
    IF DEFINED TARGET_SYSMON_VERSION (
        SET "TARGET_SYSMON_VERSION=!TARGET_SYSMON_VERSION:v=!"
        CALL :log "INFO" "action='get_target_version' status='success' version='!TARGET_SYSMON_VERSION!'"
    )
    EXIT /B 0

:get_installed_version
    SET "INSTALLED_VERSION="
    IF NOT EXIST "%INSTALLED_SYSMON_EXE%" EXIT /B 0
    "%INSTALLED_SYSMON_EXE%" -accepteula >"%TEMP_OUTPUT_FILE%" 2>&1
    IF NOT EXIST "%TEMP_OUTPUT_FILE%" EXIT /B 0
    FOR /F "tokens=3" %%v IN ('findstr /B "System Monitor" "%TEMP_OUTPUT_FILE%"') DO SET "INSTALLED_VERSION=%%v"
    IF DEFINED INSTALLED_VERSION (
        SET "INSTALLED_VERSION=!INSTALLED_VERSION:v=!"
        CALL :log "INFO" "action='get_installed_version' status='success' version='!INSTALLED_VERSION!'"
    ) ELSE (
        CALL :log "WARN" "action='get_installed_version' status='read_failed'"
    )
    EXIT /B 0

:log
    ECHO timestamp="%DATE% %TIME%" level="%~1" %~2 >> "%LOG_FILE%"
    EXIT /B 0
