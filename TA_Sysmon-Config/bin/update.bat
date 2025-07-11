@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION

REM --- ======================================================================
REM --- Configuration: Sysmon Configuration Forcer
REM --- This script directly copies and applies a new Sysmon configuration
REM --- without checking for dependencies. It assumes Sysmon is installed.
REM --- ======================================================================

REM --- The dedicated installation directory for all Sysmon components.
SET "TARGET_DIR=%WINDIR%\Sysmon"

REM --- The log file for this script's execution.
SET "LOG_FILE=%TARGET_DIR%\sysmon_config_updater.log"

REM --- Paths to the Sysmon components as they exist on the target system.
SET "INSTALLED_SYSMON_EXE=%TARGET_DIR%\Sysmon.exe"
SET "FINAL_CONFIG_FILE=%TARGET_DIR%\config.xml"

REM --- Paths to the new configuration file bundled with this script.
SET "SCRIPT_DIR=%~dp0"
SET "NEW_CONFIG_FILE=%SCRIPT_DIR%config.xml"

REM --- ======================================================================
REM --- Script Execution Start
REM --- ======================================================================

REM --- Ensure the target directory exists before any logging can occur.
IF NOT EXIST "%TARGET_DIR%" MKDIR "%TARGET_DIR%"

CALL :log "INFO" "action='script_start'"

REM --- Main execution flow.
CALL :main_execution
EXIT /B %ERRORLEVEL%

:fatal_exit
    ECHO.
    ECHO ERROR: A fatal error occurred. Please check the log file for details:
    ECHO %LOG_FILE%
    PAUSE
    EXIT /B 1

:main_execution
    CALL :log "INFO" "action='main_execution' status='started'"
    
    REM --- Step 1: Deploy the new configuration file, overwriting the old one.
    CALL :deploy_new_config
    IF %ERRORLEVEL% NEQ 0 (
        CALL :log "ERROR" "action='deploy_config' status='failed_final' message='Could not copy the new config file.'"
        GOTO :fatal_exit
    )
    
    REM --- Step 2: Apply the newly deployed configuration to Sysmon.
    CALL :apply_sysmon_config
    IF %ERRORLEVEL% NEQ 0 (
        CALL :log "ERROR" "action='apply_config' status='failed' message='Sysmon rejected the new configuration.'"
        GOTO :fatal_exit
    )
    
    CALL :log "INFO" "action='main_execution' status='completed_successfully'"
    ECHO SUCCESS: Sysmon configuration update attempted. Check logs for details.
    EXIT /B 0

REM --- ======================================================================
REM --- Subroutines
REM --- ======================================================================

:deploy_new_config
    CALL :log "INFO" "action='deploy_config' status='starting'"
    
    REM --- Check if the source configuration file exists next to the script.
    IF NOT EXIST "%NEW_CONFIG_FILE%" (
        CALL :log "ERROR" "action='deploy_config' status='source_missing' file='%NEW_CONFIG_FILE%'"
        EXIT /B 1
    )
    
    REM --- Forcefully copy the new config file, overwriting any existing one.
    COPY /Y "%NEW_CONFIG_FILE%" "%FINAL_CONFIG_FILE%" >NUL 2>&1
    IF %ERRORLEVEL% EQU 0 (
        CALL :log "INFO" "action='deploy_config' status='success' message='New config file copied to %TARGET_DIR%'"
        EXIT /B 0
    ) ELSE (
        CALL :log "ERROR" "action='deploy_config' status='copy_failed' error_code='%ERRORLEVEL%'"
        EXIT /B 1
    )

:apply_sysmon_config
    CALL :log "INFO" "action='apply_config' status='starting'"
    ECHO INFO: Applying new Sysmon configuration...
    
    REM --- Check if the Sysmon executable exists before trying to use it.
    IF NOT EXIST "%INSTALLED_SYSMON_EXE%" (
        CALL :log "ERROR" "action='apply_config' status='sysmon_exe_missing' path='%INSTALLED_SYSMON_EXE%'"
        EXIT /B 1
    )

    REM --- Use the -c switch to apply the new configuration.
    "%INSTALLED_SYSMON_EXE%" -c "%FINAL_CONFIG_FILE%" >NUL 2>&1
    SET "CONFIG_RESULT=%ERRORLEVEL%"
    
    IF %CONFIG_RESULT% EQU 0 (
        CALL :log "INFO" "action='apply_config' status='success'"
    ) ELSE (
        CALL :log "ERROR" "action='apply_config' status='failed' error_code='%CONFIG_RESULT%'"
    )
    
    EXIT /B %CONFIG_RESULT%

:log
    REM --- Simple logging function. %~1 is level, %~2 is message.
    ECHO timestamp="%DATE% %TIME%" level="%~1" %~2 >> "%LOG_FILE%"
    EXIT /B 0

ENDLOCAL
