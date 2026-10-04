# Asks for one line of text and prints it back. Used by the Action Pattern
# Library, which has no way to type a name from inside FBNeo.
#
#   powershell -NoProfile -STA -ExecutionPolicy Bypass -File name_prompt.ps1 "current name" 66
#
# -STA is REQUIRED. Windows Forms needs a single-threaded apartment, and
# PowerShell 5.1 is STA when interactive but NOT when launched with -File from
# another process; without it ShowDialog() throws.
#
# THE EMULATOR IS FROZEN THE WHOLE TIME THIS IS OPEN. io.popen is synchronous
# and runs on the emulator thread - measured at 6.6s to 39s on the file dialog
# probe (2026-09-16). The Lua side puts a notice on screen one frame before
# calling this, so the player knows where their typing is supposed to go.
#
# OUTPUT IS FENCED BY MARKERS, not by line numbers. Lua runs this with 2>&1, so
# PowerShell's own banner and anything on stderr arrive on the same stream;
# neither of them is between the two markers.
#
#   VSAV_NAME_BEGIN
#   OK | CANCELLED | ERROR: <message>
#   <the text>
#   VSAV_NAME_END

param(
  [string]$Current = '',
  [int]$Max = 66
)

$ErrorActionPreference = 'Stop'
$status = 'ERROR: never ran'
$name = ''

try {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  # KEPT ON TOP WHILE IT IS OPEN, NOT ONLY WHEN IT OPENS (user, 2026-09-30).
  #
  # TopMost alone loses to an emulator that is top-most itself (full screen, or
  # its own always-on-top): bring FBNeo forward and it covers this window, and
  # Alt+Tab did not bring it back while the emulator sat frozen on io.popen.
  # A timer below puts it back at the top of the top-most band every 300 ms.
  # SWP_NOACTIVATE: it never takes the focus - click it to type. Compiling this
  # costs about a quarter of a second (measured), while the game is stopped.
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class VsavTopmost {
  [DllImport("user32.dll")]
  static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  // HWND_TOPMOST; SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE
  public static void Keep(IntPtr hWnd) { SetWindowPos(hWnd, new IntPtr(-1), 0, 0, 0, 0, 0x0013); }
}
'@

  $f = New-Object System.Windows.Forms.Form
  $f.Text = 'VSAV Training - Pattern Name'
  # TopMost, or this opens BEHIND a full-screen emulator - which is
  # indistinguishable from a hang, because the process is blocked on a window
  # nobody can see. Same problem the file dialog had.
  $f.TopMost = $true
  $f.StartPosition = 'CenterScreen'
  $f.FormBorderStyle = 'FixedDialog'
  $f.MinimizeBox = $false
  $f.MaximizeBox = $false
  $f.ClientSize = New-Object System.Drawing.Size(470, 116)

  $lab = New-Object System.Windows.Forms.Label
  $lab.Text = "Name for this pattern. ASCII only, up to $Max characters."
  $lab.SetBounds(12, 14, 446, 20)

  $box = New-Object System.Windows.Forms.TextBox
  $box.SetBounds(12, 38, 446, 24)
  $box.Text = $Current
  $box.MaxLength = $Max

  $ok = New-Object System.Windows.Forms.Button
  $ok.Text = 'OK'
  $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
  $ok.SetBounds(302, 76, 75, 26)

  $no = New-Object System.Windows.Forms.Button
  $no.Text = 'Cancel'
  $no.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
  $no.SetBounds(383, 76, 75, 26)

  $f.Controls.AddRange(@($lab, $box, $ok, $no))
  $f.AcceptButton = $ok
  $f.CancelButton = $no
  $keep = New-Object System.Windows.Forms.Timer
  $keep.Interval = 300
  $keep.Add_Tick({ [VsavTopmost]::Keep($f.Handle) })
  $f.Add_Shown({ $f.Activate(); $box.Focus(); $box.SelectAll(); $keep.Start() })

  $answer = $f.ShowDialog()
  $keep.Stop()
  $keep.Dispose()
  if ($answer -eq [System.Windows.Forms.DialogResult]::OK) {
    $name = $box.Text
    $status = 'OK'
  } else {
    # A real answer, not a failure. The caller has to tell "the player said no"
    # apart from "PowerShell never ran", and both look the same otherwise.
    $status = 'CANCELLED'
  }
  $f.Dispose()
} catch {
  $status = 'ERROR: ' + $_.Exception.Message
}

Write-Output 'VSAV_NAME_BEGIN'
Write-Output $status
Write-Output $name
Write-Output 'VSAV_NAME_END'
