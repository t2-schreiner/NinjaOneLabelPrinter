@echo off
:: ============================================================
:: NinjaOne Asset Label Printer – Starter
:: ============================================================
:: Startet das PowerShell-Skript direkt per Doppelklick.
:: Die ExecutionPolicy wird nur für diese Sitzung auf Bypass
:: gesetzt – die systemweite Richtlinie bleibt unverändert.
:: ============================================================

pushd "%~dp0"
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0NinjaOneLabelPrinter.ps1"
popd
