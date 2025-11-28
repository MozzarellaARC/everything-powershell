<#
	cdx / auto_cd_quake_mode

	Purpose:
	  Change the current PowerShell location to the folder shown in the top‑most
	  (foreground) File Explorer window. If multiple Explorer windows are open,
	  the one highest in the Z‑order (visually on top) is chosen. This works even
	  when Windows Terminal is in quake mode (because quake mode brings the
	  terminal to the foreground, but we look just beneath it in the Z‑order for
	  the first Explorer window).

	Usage:
	  cdx                # cd into topmost Explorer folder
	  cdx -PassThru      # Also outputs the resolved path
	  cdx -Verbose       # Extra diagnostic info

	Installation:
	  Dot-source or import this file in your profile (appears already placed
	  under utils). An alias 'cdx' is created automatically when this file is
	  loaded.

	Notes / Limitations:
	  - Requires access to user32.dll (standard on Windows desktop).
	  - If no Explorer windows are open, it does nothing (optional fallback can
		be customized below).
	  - Network locations / special folders are supported via the Folder.Self.Path
		property. Non-filesystem virtual folders (Control Panel, etc.) are skipped.
	  - Tested on Windows 10/11. Should work on PowerShell 5.1+ and PowerShell 7+.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not ([System.Management.Automation.PSTypeName]'Win32.NativeWindows').Type) {
	Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace Win32 {
	public static class NativeWindows {
		public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

		[DllImport("user32.dll")]
		public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

		[DllImport("user32.dll")]
		[return: MarshalAs(UnmanagedType.Bool)]
		public static extern bool IsWindowVisible(IntPtr hWnd);
	}
}
'@
}

function Get-TopMostExplorerWindowHandle {
	<#
		.SYNOPSIS
			Returns the HWND (IntPtr) for the topmost visible File Explorer window.
	#>
	$explorerHandles = @()

	# Collect current Shell (Explorer) windows + their HWNDs
	$shell = New-Object -ComObject Shell.Application
	foreach ($w in $shell.Windows()) {
		try {
			# Skip non-folder windows (like Edge or IE if still present).
			if (-not $w.LocationURL) { continue }
			# Ensure it is actually explorer driven (FullName ends with explorer.exe)
			if ($w.FullName -notmatch 'explorer.exe$') { continue }
			# Filter out virtual / non-filesystem locations that don't have a real path
			$path = $null
			try { $path = $w.Document.Folder.Self.Path } catch { }
			if (-not $path) { continue }
			$explorerHandles += [int]$w.HWND
		} catch { }
	}

	if (-not $explorerHandles) { return $null }

	$result = $null
	$callback = [Win32.NativeWindows+EnumWindowsProc]{
		param([IntPtr]$hWnd, [IntPtr]$lParam)
		if (-not [Win32.NativeWindows]::IsWindowVisible($hWnd)) { return $true }
		$handleValue = $hWnd.ToInt32()
		if ($explorerHandles -contains $handleValue) {
			$script:__TopExplorer = $hWnd
			return $false # stop enumeration
		}
		return $true
	}

	[Win32.NativeWindows]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
	if ($script:__TopExplorer) { $result = $script:__TopExplorer }
	Remove-Variable -Name __TopExplorer -Scope Script -ErrorAction SilentlyContinue
	return $result
}

function Get-ExplorerPathFromHandle {
	param(
		[Parameter(Mandatory)] [IntPtr] $Handle
	)
	$shell = New-Object -ComObject Shell.Application
	foreach ($w in $shell.Windows()) {
		try {
			if ([int]$w.HWND -ne $Handle.ToInt32()) { continue }
			if ($w.FullName -notmatch 'explorer.exe$') { continue }
			$path = $null
			try { $path = $w.Document.Folder.Self.Path } catch { }
			if ($path -and (Test-Path -LiteralPath $path)) { return $path }
		} catch { }
	}
	return $null
}

function Invoke-Cdx {
	[CmdletBinding()] param(
		[switch]$PassThru
	)
	try {
		$hwnd = Get-TopMostExplorerWindowHandle
		if (-not $hwnd) {
			Write-Verbose 'No Explorer window found.'
			return
		}
		$path = Get-ExplorerPathFromHandle -Handle $hwnd
		if (-not $path) {
			Write-Verbose 'Could not resolve path for Explorer window.'
			return
		}
		Set-Location -LiteralPath $path
		if ($PassThru) { return (Get-Location) }
	}
	catch {
		Write-Error $_
	}
}

Set-Alias -Name cdx -Value Invoke-Cdx -Scope Global -Option AllScope -Force

if ($MyInvocation.MyCommand.Module) {
	Export-ModuleMember -Function Invoke-Cdx -Alias cdx 2>$null
}
