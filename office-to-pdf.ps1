param([string]$Kind, [string]$InputPath, [string]$OutputPath)
$ErrorActionPreference = 'Stop'
$app = $null
$document = $null
try {
  switch ($Kind) {
    'word' {
      $app = New-Object -ComObject Word.Application
      $app.AutomationSecurity = 3
      $app.DisplayAlerts = 0
      $document = $app.Documents.Open($InputPath, $false, $true, $false)
      $document.ExportAsFixedFormat($OutputPath, 17)
    }
    'excel' {
      $app = New-Object -ComObject Excel.Application
      $app.AutomationSecurity = 3
      $app.DisplayAlerts = $false
      $app.AskToUpdateLinks = $false
      $document = $app.Workbooks.Open($InputPath, 0, $true)
      $document.ExportAsFixedFormat(0, $OutputPath)
    }
    'powerpoint' {
      $app = New-Object -ComObject PowerPoint.Application
      $app.AutomationSecurity = 3
      $document = $app.Presentations.Open($InputPath, -1, 0, 0)
      $document.SaveAs($OutputPath, 32)
    }
    default { throw 'Unsupported Office format.' }
  }
  if (-not (Test-Path -LiteralPath $OutputPath)) { throw 'Office did not produce a PDF.' }
} finally {
  if ($document) {
    if ($Kind -eq 'powerpoint') { $document.Close() } else { $document.Close($false) }
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($document)
  }
  if ($app) { $app.Quit(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app) }
}
