# Microsoft Store licensing helper for the packaged Windows build.
# Usage: powershell -File store-license.ps1 status|purchase
# Prints one JSON line: {"ok":bool,"pro":bool,"error":"..."}.
# Any failure reports pro=false, so the app always falls back to the free tier.
param([Parameter(Position = 0)][string]$Mode = "status")

$ErrorActionPreference = "Stop"
$AddOnStoreId = "9N4XG9JQ0KN2"      # convertory_pro_monthly_v2 (correct TRY/ARS/etc. prices)
$AddOnOfferToken = "convertory_pro_monthly_v2"

function Out-Result($ok, $pro, $err) {
  @{ ok = $ok; pro = $pro; error = $err } | ConvertTo-Json -Compress
  exit 0
}

try {
  Add-Type -AssemblyName System.Runtime.WindowsRuntime
  Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
[ComImport, Guid("3E68D4BD-7135-4D10-8018-9FB6D9F33FA1"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IInitializeWithWindow { void Initialize(IntPtr hwnd); }
public static class StoreWin {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  public static void SetOwner(object storeContext, IntPtr hwnd) { ((IInitializeWithWindow)storeContext).Initialize(hwnd); }
}
"@

  [void][Windows.Services.Store.StoreContext, Windows.Services.Store, ContentType = WindowsRuntime]
  $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
      $_.Name -eq "AsTask" -and $_.GetParameters().Count -eq 1 -and
      $_.GetParameters()[0].ParameterType.Name -eq "IAsyncOperation``1" })[0]
  function Await($operation, [Type]$resultType) {
    $task = $asTask.MakeGenericMethod($resultType).Invoke($null, @($operation))
    [void]$task.Wait(-1)
    $task.Result
  }

  $ctx = [Windows.Services.Store.StoreContext]::GetDefault()

  if ($Mode -eq "purchase") {
    [StoreWin]::SetOwner($ctx, [StoreWin]::GetForegroundWindow())
    $result = Await ($ctx.RequestPurchaseAsync($AddOnStoreId)) ([Windows.Services.Store.StorePurchaseResult])
    # 0 = Succeeded, 1 = AlreadyPurchased
    if ([int]$result.Status -in 0, 1) { Out-Result $true $true $null }
    Out-Result $true $false ("purchase status " + [int]$result.Status)
  }

  $license = Await ($ctx.GetAppLicenseAsync()) ([Windows.Services.Store.StoreAppLicense])
  $pro = $false
  foreach ($entry in $license.AddOnLicenses) {
    $item = $entry.Value
    if (-not $item.IsActive) { continue }
    if ($entry.Key.StartsWith($AddOnStoreId) -or $item.InAppOfferToken -eq $AddOnOfferToken) { $pro = $true }
  }
  Out-Result $true $pro $null
} catch {
  Out-Result $false $false ($_.Exception.Message)
}
