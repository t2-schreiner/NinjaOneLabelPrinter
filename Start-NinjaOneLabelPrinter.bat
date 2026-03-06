@echo off
:: ============================================================
:: NinjaOne Asset Label Printer – Starter
:: ============================================================
:: Launches the PowerShell script via double-click.
:: The ExecutionPolicy is set to Bypass for this session only –
:: the system-wide policy remains unchanged.
:: POWERSHELL 7 is required!
:: ============================================================

start "" pwsh -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0NinjaOneLabelPrinter.ps1"
