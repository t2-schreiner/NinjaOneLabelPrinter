@echo off
:: ============================================================
:: NinjaOne Asset Label Printer – Starter
:: ============================================================
:: Startet das PowerShell-Skript direkt per Doppelklick.
:: Die ExecutionPolicy wird nur für diese Sitzung auf Bypass
:: gesetzt – die systemweite Richtlinie bleibt unverändert.
:: POWERSHELL 7 wird benötigt!
:: ============================================================

start "" pwsh -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0NinjaOneLabelPrinter.ps1"
