@ECHO OFF
SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION

REM --- ======================================================================
REM --- Sysmon Configuration Forcer
REM --- Copies the authoritative config into the Sysmon directory and applies
REM --- it to the running service. It assumes Sysmon is already installed
REM --- (handled by TA-Sysmon-Installer).
REM ---
REM --- Config source follows the standard Splunk default/local pattern:
REM ---   local\config.xml   -> user override (wins if present)
REM ---   default\config.xml -> minimal config shipped with the app
REM ---
REM --- Runs non-interactively under Splunk (no PAUSE), and keeps all decision
REM --- logic in subroutines using EXIT /B to avoid GOTO-inside-parentheses,
REM --- a well-known source of CMD parser bugs.
REM --- ======================================================================
SET "TARGET_DIR=%WINDIR%\Sysmon"
SET "LOG_FILE=%TARGET_DIR%\sysmon_config_updater.log"

SET "INSTALLED_SYSMON_EXE=%TARGET_DIR%\Sysmon.exe"
SET "FINAL_CONFIG_FILE=%TARGET_DIR%\config.xml"

SET "SCRIPT_DIR=%~dp0"
SET "ADDON_ROOT_DIR=%SCRIPT_DIR%..\"
SET "LOCAL_CONF_FILE=%ADDON_ROOT_DIR%local\config.xml"
SET "DEFAULT_CONF_FILE=%ADDON_ROOT_DIR%default\config.xml"
SET "SOURCE_CONFIG_FILE="

REM --- ======================================================================
REM --- Entry point
REM --- ======================================================================
IF NOT EXIST "%TARGET_DIR%" MKDIR "%TARGET_DIR%"
CALL :log "INFO" "action='script_start'"
CALL :main
CALL :log "INFO" "action='script_end' status='finished'"
ENDLOCAL
GOTO :EOF

:main
    CALL :resolve_source_config
    IF NOT DEFINED SOURCE_CONFIG_FILE (
        CALL :log "ERROR" "action='config_check' status='fatal' message='No config.xml found in local or default directories.'"
        EXIT /B 1
    )
    CALL :deploy_new_config
    IF ERRORLEVEL 1 (
        CALL :log "ERROR" "action='deploy_config' status='failed_final' message='Could not copy the new config file.'"
        EXIT /B 1
    )
    CALL :apply_sysmon_config
    IF ERRORLEVEL 1 (
        CALL :log "ERROR" "action='apply_config' status='failed' message='Sysmon rejected the new configuration.'"
        EXIT /B 1
    )
    CALL :log "INFO" "action='main_execution' status='completed_successfully'"
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
    EXIT /B 0

:deploy_new_config
    CALL :log "INFO" "action='deploy_config' status='starting'"
    COPY /Y "!SOURCE_CONFIG_FILE!" "%FINAL_CONFIG_FILE%" >NUL 2>&1
    IF ERRORLEVEL 1 (
        CALL :log "ERROR" "action='deploy_config' status='copy_failed' error_code='!ERRORLEVEL!'"
        EXIT /B 1
    )
    CALL :log "INFO" "action='deploy_config' status='success' source='!SOURCE_CONFIG_FILE!'"
    EXIT /B 0

:apply_sysmon_config
    CALL :log "INFO" "action='apply_config' status='starting'"
    IF NOT EXIST "%INSTALLED_SYSMON_EXE%" (
        CALL :log "ERROR" "action='apply_config' status='sysmon_exe_missing' path='%INSTALLED_SYSMON_EXE%'"
        EXIT /B 1
    )
    "%INSTALLED_SYSMON_EXE%" -c "%FINAL_CONFIG_FILE%" >NUL 2>&1
    IF ERRORLEVEL 1 (
        CALL :log "ERROR" "action='apply_config' status='failed' error_code='!ERRORLEVEL!'"
        EXIT /B 1
    )
    CALL :log "INFO" "action='apply_config' status='success'"
    EXIT /B 0

:log
    ECHO timestamp="%DATE% %TIME%" level="%~1" %~2 >> "%LOG_FILE%"
    EXIT /B 0
