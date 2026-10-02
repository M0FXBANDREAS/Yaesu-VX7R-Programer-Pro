try {
# VX-7 clone protocol and memory map cross-checked against CHIRP's VX7 driver.
# GPL-3.0-or-later; see protocol-reference sources and LICENSE-NOTICE.txt.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$script:serial=$null;$script:image=$null;$script:reading=$false
$script:raw=New-Object IO.MemoryStream
$script:lengths=@(10,8,16193);$script:stage=0;$script:blockCount=0;$script:first=$true
$script:logPath=Join-Path $PSScriptRoot 'VX7R-error.log'
function Write-Log($text){try{Add-Content -LiteralPath $script:logPath -Value ((Get-Date -Format o)+' '+$text) -Encoding UTF8}catch{}}
$form=New-Object Windows.Forms.Form
$form.Text='Yaesu VX-7R Control';$form.FormBorderStyle='Sizable';$form.StartPosition='CenterScreen';$form.AutoScaleMode='None'
$form.BackColor=[Drawing.Color]::Black;$form.ClientSize=New-Object Drawing.Size(1536,1024);$form.MinimumSize=New-Object Drawing.Size(1000,700)
$screen=[Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$initialScale=[Math]::Min(1.0,[Math]::Min(($screen.Width-32)/1536.0,($screen.Height-80)/990.0))
$form.ClientSize=New-Object Drawing.Size([int](1536*$initialScale),[int](990*$initialScale))
$picture=New-Object Windows.Forms.PictureBox;$picture.Dock='None';$picture.SizeMode='StretchImage'
$picture.Image=[Drawing.Image]::FromFile((Join-Path $PSScriptRoot 'dashboard.jpg'));$form.Controls.Add($picture)
$ink=[Drawing.Color]::FromArgb(220,231,240);$panelColor=[Drawing.Color]::FromArgb(9,24,34)
$com=New-Object Windows.Forms.ComboBox;$com.DropDownStyle='DropDownList';$com.BackColor=$panelColor;$com.ForeColor=$ink;$com.FlatStyle='Flat'
function Refresh-Ports{try{$com.Items.Clear();foreach($p in [IO.Ports.SerialPort]::GetPortNames() | Sort-Object){[void]$com.Items.Add($p)};if($com.Items.Count){$com.SelectedIndex=0};Write-Log ('Ports: '+([IO.Ports.SerialPort]::GetPortNames() -join ', '))}catch{Write-Log $_.Exception.ToString();$status.Text='COM enumeration failed: '+$_.Exception.Message}}
$refresh=New-Object Windows.Forms.Button;$refresh.Text='Refresh COM';$refresh.Add_Click({Refresh-Ports})
$read=New-Object Windows.Forms.Button;$read.Text='Read Radio'
$cancel=New-Object Windows.Forms.Button;$cancel.Text='Cancel Read';$cancel.Enabled=$false
$save=New-Object Windows.Forms.Button;$save.Text='Save Image';$save.Enabled=$false
foreach($button in @($read,$cancel,$save,$refresh)){$button.FlatStyle='Flat';$button.BackColor=[Drawing.Color]::FromArgb(15,55,92);$button.ForeColor=$ink;$button.FlatAppearance.BorderColor=[Drawing.Color]::FromArgb(60,93,120)}
$connection=New-Object Windows.Forms.Label;$connection.Text='Disconnected';$connection.BackColor=$panelColor;$connection.ForeColor=$ink;$connection.TextAlign='MiddleLeft'
$instructions=New-Object Windows.Forms.Label;$instructions.BackColor=$panelColor;$instructions.ForeColor=$ink
$instructions.Text="READ RADIO`r`n1. Radio OFF; connect cable.`r`n2. Hold MON/F + power ON: CLONE.`r`n3. Choose COM, click Read Radio.`r`n4. Press BAND on the radio.`r`n19200 baud / 8N1. LCD frequencies above are artwork.`r`nRadio writing is not implemented."
$status=New-Object Windows.Forms.Label;$status.Text='Ready. Select COM, then Read Radio.';$status.BackColor=$panelColor;$status.ForeColor=$ink
$progress=New-Object Windows.Forms.ProgressBar;$progress.Maximum=16211
$grid=New-Object Windows.Forms.DataGridView;$grid.ReadOnly=$true;$grid.SelectionMode='FullRowSelect';$grid.MultiSelect=$false;$grid.AllowUserToDeleteRows=$false;$grid.AllowUserToAddRows=$false;$grid.RowHeadersVisible=$false;$grid.AutoSizeColumnsMode='Fill';$grid.BackgroundColor=$panelColor;$grid.BorderStyle='None'
$grid.EnableHeadersVisualStyles=$false;$grid.ColumnHeadersDefaultCellStyle.BackColor=$panelColor;$grid.ColumnHeadersDefaultCellStyle.ForeColor=$ink
$grid.DefaultCellStyle.BackColor=$panelColor;$grid.DefaultCellStyle.ForeColor=$ink;$grid.DefaultCellStyle.SelectionBackColor=[Drawing.Color]::FromArgb(22,87,153)
foreach($c in @('Channel','Frequency MHz','Mode','Name','Duplex','Offset MHz','Skip')){[void]$grid.Columns.Add($c,$c)}
$script:controls=@(
 @($com,1096,38,255,31),@($connection,1370,38,151,31),@($refresh,1428,310,99,39),
 @($read,402,731,134,46),@($cancel,548,731,140,46),@($save,1100,731,103,46),
 @($grid,402,398,805,322),@($instructions,1046,806,476,181),@($progress,710,977,313,13),@($status,5,998,1526,26)
)
$script:uiFont=New-Object Drawing.Font('Segoe UI',9,[Drawing.FontStyle]::Regular)
foreach($item in $script:controls){$item[0].Font=$script:uiFont;$form.Controls.Add($item[0]);$item[0].BringToFront()}
function Resize-Dashboard{
 # Native Windows titlebar replaces the first 34 pixels of the artwork.
 # Source artwork remains intact; rendering clips its redundant titlebar.
 $scale=[Math]::Min($form.ClientSize.Width/1536.0,$form.ClientSize.Height/990.0)
 $ox=($form.ClientSize.Width-1536*$scale)/2;$oy=($form.ClientSize.Height-990*$scale)/2
 $picture.Bounds=New-Object Drawing.Rectangle([int]$ox,[int]($oy-34*$scale),[int](1536*$scale),[int](1024*$scale))
 foreach($item in $script:controls){$item[0].Bounds=New-Object Drawing.Rectangle([int]($ox+$item[1]*$scale),[int]($oy+($item[2]-34)*$scale),[int]($item[3]*$scale),[int]($item[4]*$scale))}
}
$form.Add_Resize({Resize-Dashboard})
$picture.Add_MouseClick({param($sender,$event)
 $scale=$picture.ClientSize.Width/1536.0;$x=$event.X/$scale;$y=$event.Y/$scale
 if($y -lt 34){if($x -gt 1483){$form.Close()}elseif($x -gt 1435){if($form.WindowState -eq 'Maximized'){$form.WindowState='Normal'}else{$form.WindowState='Maximized'}}elseif($x -gt 1387){$form.WindowState='Minimized'}}
})
$form.KeyPreview=$true;$form.Add_KeyDown({param($sender,$event)if($event.KeyCode -eq 'Escape' -and !$script:reading){$form.Close()}})
Resize-Dashboard
function Stop-Read($text){
 $script:reading=$false
 if($script:serial){try{$script:serial.Close()}catch{};$script:serial.Dispose();$script:serial=$null}
 $grid.ReadOnly=$false;$read.Enabled=$true;$refresh.Enabled=$true;$com.Enabled=$true;$cancel.Enabled=$false;$status.Text=$text;$connection.Text='Disconnected'
}
function Get-Bcd($data,$offset){
 $value=0
 for($i=0;$i -lt 3;$i++){$b=[int]$data[$offset+$i];$hi=$b -shr 4;$lo=$b -band 15;if($hi -gt 9 -or $lo -gt 9){throw 'Invalid BCD in channel frequency.'};$value=$value*100+$hi*10+$lo}
 return $value
}
function Check-Image($data){
 if($data.Length -ne 16211){throw ('Incomplete image: '+$data.Length+' / 16211 bytes')}
 foreach($range in @(@(0x592,0x610,0x611),@(0x612,0x690,0x691),@(0,0x3F51,0x3F52))){
  $sum=0;for($i=$range[0];$i -le $range[1];$i++){$sum=($sum+[int]$data[$i]) -band 255}
  if($sum -ne [int]$data[$range[2]]){throw ('Checksum mismatch at 0x'+$range[2].ToString('X'))}
 }
}
$script:invariant=[Globalization.CultureInfo]::InvariantCulture
$script:tones=@(67.0,69.3,71.9,74.4,77.0,79.7,82.5,85.4,88.5,91.5,94.8,97.4,100.0,103.5,107.2,110.9,114.8,118.8,123.0,127.3,131.8,136.5,141.3,146.2,151.4,156.7,159.8,162.2,165.5,167.9,171.3,173.8,177.3,179.9,183.5,186.2,189.9,192.8,196.6,199.5,203.5,206.5,210.7,218.1,225.7,229.1,233.6,241.8,250.3,254.1)
$script:dcs=@(23,25,26,31,32,36,43,47,51,53,54,65,71,72,73,74,114,115,116,122,125,131,132,134,143,145,152,155,156,162,165,172,174,205,212,223,225,226,243,244,245,246,251,252,255,261,263,265,266,271,274,306,311,315,325,331,332,343,346,351,356,364,365,371,411,412,413,423,431,432,445,446,452,454,455,462,464,465,466,503,506,516,523,526,532,546,565,606,612,624,627,631,632,654,662,664,703,712,723,731,732,734,743,754)
$script:original=$null;$script:dirty=$false;$script:writing=$false;$script:expectedWrite=$null
$script:modes=@('FM','AM','WFM','Auto');$script:duplexes=@('','-','+','split');$script:steps=@(5.0,10.0,12.5,15.0,20.0,25.0,50.0,100.0,9.0)
$script:charset='0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz.,:;!"#$%&''()*+-.=<>?@[?]^_\{|}'
function Has-Image {if(!$script:image){$status.Text='Read your radio or open its saved image first.';return $false};if($script:reading -or $script:writing){$status.Text='Wait for the current transfer.';return $false};return $true}
function Mark-Dirty{$script:expectedWrite=$null;$script:dirty=$true;$save.Enabled=$true;$write.Enabled=$true;$status.Text='Image changed locally. Save or Write Radio to apply.'}
function Update-Checksums($data){foreach($range in @(@(0x592,0x610,0x611),@(0x612,0x690,0x691),@(0,0x3F51,0x3F52))){$sum=0;for($i=$range[0];$i -le $range[1];$i++){$sum=($sum+[int]$data[$i]) -band 255};$data[$range[2]]=[byte]$sum}}
function Get-Flag($data,$number){$i=$number-1;$value=[int]$data[0x1202+[int][Math]::Floor($i/2)];if(($i%2) -eq 0){return ($value -band 15)};return (($value -shr 4) -band 15)}
function Set-Flag($data,$number,$bits){$i=$number-1;$at=0x1202+[int][Math]::Floor($i/2);if(($i%2) -eq 0){$data[$at]=[byte](([int]$data[$at] -band 240) -bor $bits)}else{$data[$at]=[byte](([int]$data[$at] -band 15) -bor ($bits -shl 4))}}
function Set-Bcd($data,$at,$khz){$value=[int][Math]::Floor($khz);if($value -lt 0 -or $value -gt 999999){throw 'Frequency/offset cannot be encoded.'};for($i=2;$i -ge 0;$i--){$pair=$value%100;$data[$at+$i]=[byte](([int][Math]::Floor($pair/10) -shl 4) -bor ($pair%10));$value=[int][Math]::Floor($value/100)}}
function Selected-Number{if($grid.CurrentCell -and $grid.CurrentCell.RowIndex -ge 0){return [int]$grid.Rows[$grid.CurrentCell.RowIndex].Cells[0].Value};if($grid.SelectedRows.Count){return [int]$grid.SelectedRows[0].Cells[0].Value};return 0}
function Remove-Bank-Member($data,$number){for($bank=0;$bank -lt 9;$bank++){$any=$false;for($j=0;$j -lt 48;$j++){$at=0xEA2+$bank*96+$j*2;$member=([int]$data[$at] -shl 8) -bor [int]$data[$at+1];if($member -eq $number-1){$data[$at]=255;$data[$at+1]=255}elseif($member -ne 65535){$any=$true}};if(!$any){$data[0x742+$bank*2]=255;$data[0x743+$bank*2]=255}}}
function Read-Channel($data,$n){
 $o=0x1322+($n-1)*22;$flags=Get-Flag $data $n;$name=''
 for($j=0;$j -lt 8;$j++){$v=[int]$data[$o+6+$j];if($v -eq 255){break};if($v -lt $script:charset.Length){$name+=$script:charset[$v]}}
 $ti=[int]$data[$o+18] -band 63;$di=[int]$data[$o+19] -band 127;$si=[int]$data[$o+1] -band 15
 $tm=[int]$data[$o+20] -band 3;$split=([int]$data[$o+20] -band 4) -ne 0
 $toneMode=@('Off','Tone','TSQL','DTCS')[$tm];if($split){$toneMode='Cross (preserve)'}
 $skip='';if($flags -band 8){$skip='P'}elseif($flags -band 4){$skip='S'}
 return [pscustomobject]@{Channel=$n;Frequency=((Get-Bcd $data ($o+2))/1000.0).ToString('F3',$script:invariant);Mode=$script:modes[[int]$data[$o+5] -band 3];Name=$name.TrimEnd();Duplex=$script:duplexes[([int]$data[$o+1] -shr 4) -band 3];Offset=((Get-Bcd $data ($o+15))/1000.0).ToString('F3',$script:invariant);ToneMode=$toneMode;Tone=$script:tones[$ti];DCS=$script:dcs[$di];Step=$script:steps[$si];Power=([int]$data[$o+1] -shr 6);Skip=$skip}
}
function Write-Channel($data,$item){
 $n=[int]$item.Channel;if($n -lt 1 -or $n -gt 450){throw 'Channel must be 1–450.'}
 $freq=[double]::Parse([string]$item.Frequency,$script:invariant);$offset=[double]::Parse([string]$item.Offset,$script:invariant)
 if($freq -lt 0.5 -or $freq -gt 999){throw 'Frequency must be 0.5–999 MHz.'};if($offset -lt 0 -or $offset -gt 999.999){throw 'Offset must be a positive magnitude (use Duplex for sign).'}
 $mi=[Array]::IndexOf($script:modes,[string]$item.Mode);$du=[Array]::IndexOf($script:duplexes,[string]$item.Duplex);$step=[double]::Parse([string]$item.Step,$script:invariant);$si=[Array]::IndexOf($script:steps,$step)
 $ti=[Array]::IndexOf($script:tones,[double]::Parse([string]$item.Tone,$script:invariant));$di=[Array]::IndexOf($script:dcs,[int]$item.DCS);$power=[int]$item.Power
 if($mi -lt 0 -or $du -lt 0 -or $si -lt 0 -or $ti -lt 0 -or $di -lt 0 -or $power -lt 0 -or $power -gt 3){throw 'Invalid mode, duplex, step, tone, DCS or power.'}
 if($freq -ge 222 -and $freq -le 225 -and $power -gt 1){throw 'For 222–225 MHz use power 0 or 1 (50 mW / 300 mW on USA model).'}
 $name=[string]$item.Name;if($name.Length -gt 8){throw 'Name must be at most 8 characters.'};foreach($c in $name.ToCharArray()){if($script:charset.IndexOf($c) -lt 0){throw ('Unsupported name character: '+$c)}}
 $tm=[Array]::IndexOf(@('Off','Tone','TSQL','DTCS'),[string]$item.ToneMode);if($tm -lt 0 -and $item.ToneMode -ne 'Cross (preserve)'){throw 'Invalid tone mode.'}
 if([string]$item.Skip -notin @('','S','P')){throw 'Skip must be blank, S or P.'}
 $o=0x1322+($n-1)*22;$bits=Get-Flag $data $n
 if(($bits -band 2) -eq 0){for($j=0;$j -lt 22;$j++){$data[$o+$j]=0};$data[$o]=5;$data[$o+5]=48;Remove-Bank-Member $data $n}
 $data[$o+1]=[byte](($power -shl 6) -bor ($du -shl 4) -bor $si)
 Set-Bcd $data ($o+2) ($freq*1000);Set-Bcd $data ($o+15) ($offset*1000)
 $data[$o+5]=[byte](([int]$data[$o+5] -band 252) -bor $mi)
 for($j=0;$j -lt 8;$j++){$data[$o+6+$j]=[byte]$script:charset.IndexOf($name.PadRight(8)[$j])}
 $data[$o+18]=[byte](([int]$data[$o+18] -band 192) -bor $ti);$data[$o+19]=[byte](([int]$data[$o+19] -band 128) -bor $di)
 if($tm -ge 0){$data[$o+20]=[byte](([int]$data[$o+20] -band 248) -bor $tm)}
 $bits=3;if($item.Skip -eq 'S'){$bits=$bits -bor 4};if($item.Skip -eq 'P'){$bits=$bits -bor 8};Set-Flag $data $n $bits
}
function Refresh-MemoryGrid($select){$count=Show-Memories $script:image;foreach($row in $grid.Rows){if([int]$row.Cells[0].Value -eq $select){$grid.ClearSelection();$row.Selected=$true;$grid.CurrentCell=$row.Cells[0];break}};return $count}
function Load-Editor{
 if($script:refreshingGrid){return};$n=Selected-Number;if(!$script:image -or !$n){return}
 try{$item=Read-Channel $script:image $n;foreach($key in $script:fields.Keys){$script:fields[$key].Text=[string]$item.$key};$channelLabel.Text=('Channel '+$n);$script:selectedChannel=$n}catch{$status.Text='Editor: '+$_.Exception.Message}
}
function Apply-Editor{
 if(!(Has-Image)){return};$n=Selected-Number;if(!$n){return}
 try{$record=[ordered]@{Channel=$n};foreach($key in $script:fields.Keys){$record[$key]=$script:fields[$key].Text};$copy=[byte[]]$script:image.Clone();Write-Channel $copy ([pscustomobject]$record);Update-Checksums $copy;Check-Image $copy;$script:image=$copy;[void](Refresh-MemoryGrid $n);Mark-Dirty}catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Edit rejected')}
}
function New-Channel{
 if(!(Has-Image)){return};$n=0;for($i=1;$i -le 450;$i++){if(((Get-Flag $script:image $i) -band 3) -ne 3){$n=$i;break}};if(!$n){$status.Text='All 450 regular memories are in use.';return}
 try{$copy=[byte[]]$script:image.Clone();Write-Channel $copy ([pscustomobject]@{Channel=$n;Frequency='145.500';Mode='FM';Name='';Duplex='';Offset='0';ToneMode='Off';Tone='67.0';DCS=23;Step='12.5';Power=0;Skip=''});Update-Checksums $copy;$script:image=$copy;[void](Refresh-MemoryGrid $n);Mark-Dirty}catch{$status.Text=$_.Exception.Message}
}
function Delete-Channel{
 if(!(Has-Image)){return};$n=Selected-Number;if(!$n){return}
 if([Windows.Forms.MessageBox]::Show(('Delete memory '+$n+' from the working image?'),'Delete','YesNo') -ne 'Yes'){return}
 Set-Flag $script:image $n ((Get-Flag $script:image $n) -band 14);Remove-Bank-Member $script:image $n;Update-Checksums $script:image;[void](Refresh-MemoryGrid 0);Mark-Dirty
}
function Open-Image{
 if($script:reading -or $script:writing){return}
 if($script:dirty -and [Windows.Forms.MessageBox]::Show('Discard unsaved image edits?','Open image','YesNo') -ne 'Yes'){return}
 $d=New-Object Windows.Forms.OpenFileDialog;$d.Filter='VX-7R image (*.img)|*.img'
 if($d.ShowDialog() -eq 'OK'){try{$data=[IO.File]::ReadAllBytes($d.FileName);Check-Image $data;$script:image=$data;$script:original=[byte[]]$data.Clone();$script:dirty=$false;$script:expectedWrite=$null;$save.Enabled=$true;$write.Enabled=$true;[void](Refresh-MemoryGrid 0);$status.Text='Opened '+$d.FileName}catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Invalid image')}};$d.Dispose()
}
function Export-Channels{
 if(!(Has-Image)){return};$d=New-Object Windows.Forms.SaveFileDialog;$d.Filter='VX-7 dashboard CSV (*.csv)|*.csv';$d.FileName='VX7R-channels.csv'
 if($d.ShowDialog() -eq 'OK'){try{$records=@(foreach($row in $grid.Rows){Read-Channel $script:image ([int]$row.Cells[0].Value)});$records | Export-Csv -LiteralPath $d.FileName -NoTypeInformation -Encoding UTF8;$status.Text='Exported '+$records.Count+' channels.'}catch{$status.Text=$_.Exception.Message}};$d.Dispose()
}
function Import-Channels{
 if(!(Has-Image)){return};$d=New-Object Windows.Forms.OpenFileDialog;$d.Filter='VX-7 dashboard CSV (*.csv)|*.csv'
 if($d.ShowDialog() -eq 'OK'){try{$items=@(Import-Csv -LiteralPath $d.FileName);if(!$items.Count -or $items.Count -gt 450){throw 'CSV must contain 1–450 channels.'};$copy=[byte[]]$script:image.Clone();$numbers=@{};foreach($item in $items){if($numbers.ContainsKey([int]$item.Channel)){throw 'Duplicate channel in CSV.'};$numbers[[int]$item.Channel]=$true;Write-Channel $copy $item};Update-Checksums $copy;Check-Image $copy;$script:image=$copy;[void](Refresh-MemoryGrid 0);Mark-Dirty;$status.Text='Imported '+$items.Count+' channels into working image.'}catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Import rejected; no image changes applied')}};$d.Dispose()
}
function Edit-Banks{
 if(!(Has-Image)){return};$n=Selected-Number;if(!$n){$status.Text='Select a channel first.';return}
 $dialog=New-Object Windows.Forms.Form;$dialog.Text='Memory '+$n+' - bank membership';$dialog.Size=New-Object Drawing.Size(340,390);$dialog.StartPosition='CenterParent'
 $list=New-Object Windows.Forms.CheckedListBox;$list.Dock='Fill';$list.CheckOnClick=$true
 for($bank=0;$bank -lt 9;$bank++){$present=$false;for($j=0;$j -lt 48;$j++){$at=0xEA2+$bank*96+$j*2;$v=([int]$script:image[$at] -shl 8) -bor [int]$script:image[$at+1];if($v -eq $n-1){$present=$true}};[void]$list.Items.Add(('MG'+($bank+1)),$present)}
 $ok=New-Object Windows.Forms.Button;$ok.Text='Apply';$ok.Dock='Bottom';$ok.DialogResult='OK';$dialog.Controls.Add($list);$dialog.Controls.Add($ok)
 if($dialog.ShowDialog($form) -eq 'OK'){try{$copy=[byte[]]$script:image.Clone();Remove-Bank-Member $copy $n;foreach($bank in $list.CheckedIndices){$slot=-1;for($j=0;$j -lt 48;$j++){$at=0xEA2+$bank*96+$j*2;if($copy[$at] -eq 255 -and $copy[$at+1] -eq 255){$slot=$at;break}};if($slot -lt 0){throw ('MG'+($bank+1)+' is full (48 members).')};$copy[$slot]=[byte](($n-1) -shr 8);$copy[$slot+1]=[byte](($n-1) -band 255);$copy[0x742+$bank*2]=0;$copy[0x743+$bank*2]=0};Update-Checksums $copy;$script:image=$copy;Mark-Dirty}catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Bank edit rejected')}};$dialog.Dispose()
}
function Backup-Original($data){
 $folder=Join-Path $PSScriptRoot 'Backups';[void][IO.Directory]::CreateDirectory($folder);$file=Join-Path $folder ('VX7R-original-'+[DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff')+'.img');[IO.File]::WriteAllBytes($file,$data);Write-Log ('Original backed up: '+$file)
}
function Start-Write{
 if(!$grid.EndEdit()){return}
 if(!(Has-Image)){return};if(!$com.SelectedItem){$status.Text='Select COM port.';return}
 try{if(!$script:original){throw 'No original image available. Read your radio first.'};Check-Image $script:original;Update-Checksums $script:image;Check-Image $script:image;Backup-Original $script:original}catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Write blocked');return}
 $text="Write this image to your VX-7R? This replaces radio memories/settings.`r`nOriginal image is saved in Backups.`r`n`r`nRadio OFF, cable connected. Hold MON/F while turning ON: CLONE.`r`nPress V/M on the radio: CLONE WAIT. Then click Yes here.`r`nUse an image read from this same radio. After writing, read it back to verify."
 if([Windows.Forms.MessageBox]::Show($text,'Write Radio','YesNo','Warning') -ne 'Yes'){return}
 $candidate=$null
 try{$candidate=New-Object -TypeName IO.Ports.SerialPort -ArgumentList @([string]$com.SelectedItem,19200,[IO.Ports.Parity]::None,8,[IO.Ports.StopBits]::One);$candidate.Handshake='None';$candidate.ReadTimeout=100;$candidate.WriteTimeout=1000;$candidate.DtrEnable=$false;$candidate.RtsEnable=$false;$candidate.Open();$candidate.DiscardInBuffer();$script:serial=$candidate
  $search.Text='';$script:expectedWrite=[byte[]]$script:image.Clone();$script:writing=$true;$script:txStage=0;$script:txPosition=0;$script:ackBytes=New-Object 'System.Collections.Generic.List[byte]';$script:txTime=[DateTime]::UtcNow;$script:txLastRx=$script:txTime
  Write-Log ('Upload started on '+$com.SelectedItem+'; header 1 TX: '+[BitConverter]::ToString($script:expectedWrite,0,10))
  $grid.ReadOnly=$true;$script:serial.Write($script:expectedWrite,0,10);$read.Enabled=$false;$write.Enabled=$false;$save.Enabled=$false;$com.Enabled=$false;$refresh.Enabled=$false;$cancel.Enabled=$true;$connection.Text='Writing';$progress.Value=10;$status.Text='Writing header; waiting for radio acknowledgement.'
 }catch{Write-Log $_.Exception.ToString();if($candidate){$candidate.Dispose()};$script:writing=$false;Stop-Read ('Write failed: '+$_.Exception.Message);$write.Enabled=$true;$save.Enabled=$true}
}
function Get-HeaderReplyState($received,$expected){
 $n=$received.Count;$size=$expected.Length
 if($n -eq 0){return 'Waiting'}
 # ACK may arrive before or after the cable echo. A byte within the echo
 # must never be taken as the radio's ACK.
 $ackFirst=$received[0] -eq 6
 if($ackFirst -and $n -eq 1){return 'AckOnly'}
 if($ackFirst){
  $take=[Math]::Min($size,$n-1)
  for($j=0;$j -lt $take;$j++){if($received[$j+1] -ne $expected[$j]){return 'Unexpected'}}
  if($n -eq $size+1){return 'AckAndEcho'}
  if($n -gt $size+1){return 'Unexpected'}
  return 'Waiting'
 }
 $take=[Math]::Min($size,$n)
 for($j=0;$j -lt $take;$j++){if($received[$j] -ne $expected[$j]){return 'Unexpected'}}
 if($n -lt $size){return 'Waiting'}
 if($n -eq $size){return 'EchoOnly'}
 if($n -eq $size+1 -and $received[$size] -eq 6){return 'EchoAndAck'}
 return 'Unexpected'
}
function Write-Tick{
 if(!$script:writing -or !$script:serial){return}
 try{
  $now=[DateTime]::UtcNow
  if($script:txStage -lt 2){
   $blockLength=$script:lengths[$script:txStage]
   while($script:serial.BytesToRead -gt 0){
    $v=$script:serial.ReadByte();$script:ackBytes.Add([byte]$v);$script:txLastRx=[DateTime]::UtcNow
    if($script:ackBytes.Count -gt $blockLength+1){break}
   }
   $expected=New-Object byte[] $blockLength;[Array]::Copy($script:expectedWrite,$script:txPosition,$expected,0,$blockLength)
   $state=Get-HeaderReplyState $script:ackBytes $expected
   $quiet=([DateTime]::UtcNow-$script:txLastRx).TotalMilliseconds
   # Allow a short receive quiet period so ACK-before-echo is not passed
   # on to the next block as an orphaned echo.
   if($state -in @('AckOnly','AckAndEcho','EchoAndAck') -and $quiet -ge 100){
    Write-Log ('Header '+($script:txStage+1)+' RX ('+$state+'): '+[BitConverter]::ToString($script:ackBytes.ToArray()))
    $script:txPosition+=$blockLength;$script:txStage++;$script:ackBytes.Clear();$script:txTime=[DateTime]::UtcNow;$script:txLastRx=$script:txTime
    if($script:txStage -lt 2){Write-Log ('Header '+($script:txStage+1)+' TX: '+[BitConverter]::ToString($script:expectedWrite,$script:txPosition,$script:lengths[$script:txStage]));$script:serial.Write($script:expectedWrite,$script:txPosition,$script:lengths[$script:txStage])}
   }elseif($state -eq 'Unexpected' -and $quiet -ge 100){
    $rx=[BitConverter]::ToString($script:ackBytes.ToArray());Write-Log ('Unexpected header '+($script:txStage+1)+' reply: '+$rx+'; expected echo: '+[BitConverter]::ToString($expected))
    throw ('Header '+($script:txStage+1)+' returned unexpected bytes ('+$rx+'). See VX7R-error.log. Re-enter CLONE WAIT before retrying.')
   }elseif(([DateTime]::UtcNow-$script:txTime).TotalSeconds -gt 5){
    $rx=[BitConverter]::ToString($script:ackBytes.ToArray());Write-Log ('Header '+($script:txStage+1)+' timed out; state '+$state+'; RX '+$rx)
    if($state -eq 'EchoOnly'){throw 'The cable echoed the header, but the radio did not ACK. Re-enter CLONE WAIT by pressing V/M before Write Radio.'}
    throw ('No complete radio ACK for header '+($script:txStage+1)+'. Check CLONE WAIT, cable seating and COM port. See VX7R-error.log.')
   }
  }else{
   if($script:serial.BytesToRead -gt 0){$script:serial.DiscardInBuffer()}
   if(($now-$script:txTime).TotalMilliseconds -lt 30){return}
   $n=[Math]::Min(8,16211-$script:txPosition)
   if($n -gt 0){$script:serial.Write($script:expectedWrite,$script:txPosition,$n);$script:txPosition+=$n;$script:txTime=$now;$progress.Value=$script:txPosition;$status.Text='Writing '+$script:txPosition+' / 16211 bytes. Keep cable connected.'}
   elseif($script:serial.BytesToWrite -eq 0){$script:writing=$false;Stop-Read 'Image sent. Check the radio shows CLONE, then Read Radio to verify the written image.';$write.Enabled=$true;$save.Enabled=$true;$connection.Text='Read-back needed';$script:dirty=$false;Write-Log 'Image sent; radio read-back verification pending.'}
  }
 }catch{Write-Log $_.Exception.ToString();$script:writing=$false;Stop-Read ('Write failed: '+$_.Exception.Message);$write.Enabled=$true;$save.Enabled=$true;[void][Windows.Forms.MessageBox]::Show(($_.Exception.Message+"`r`nPlease send VX7R-error.log if this repeats."),'Write failed')}
}

function Show-Memories($data){
 Update-VfoDisplays $data
 $script:refreshingGrid=$true;$grid.Rows.Clear();$modes=@('FM','AM','WFM','Auto');$duplex=@('','-','+','split')
 $charset='0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz.,:;!"#$%&''()*+-.=<>?@[?]^_\{|}'
 $shown=0
 for($number=1;$number -le 450;$number++){
  $index=$number-1;$flag=[int]$data[0x1202+[int][Math]::Floor($index/2)]
  if(($index % 2) -eq 0){$bits=$flag -band 15}else{$bits=($flag -shr 4) -band 15}
  if(($bits -band 3) -ne 3){continue}
  $o=0x1322+$index*22;$name=''
  for($j=0;$j -lt 8;$j++){$v=[int]$data[$o+6+$j];if($v -eq 255){break};if($v -lt $charset.Length){$name += $charset[$v]}else{$name+='?'}}
  try{
   $freq=(Get-Bcd $data ($o+2))/1000.0;$offset=(Get-Bcd $data ($o+15))/1000.0
   $mode=$modes[[int]$data[$o+5] -band 3];$dup=$duplex[([int]$data[$o+1] -shr 4) -band 3]
   $skip='';if($bits -band 8){$skip='P'}elseif($bits -band 4){$skip='S'}
   [void]$grid.Rows.Add([object[]]@($number,$freq.ToString('F3',[Globalization.CultureInfo]::InvariantCulture),$mode,$name.TrimEnd(),$dup,$offset.ToString('F3',[Globalization.CultureInfo]::InvariantCulture),$skip));$shown++
  }catch{[void]$grid.Rows.Add([object[]]@($number,'Decode error','','','','',''))}
 }
 $script:refreshingGrid=$false
 if($grid.Rows.Count){$grid.CurrentCell=$grid.Rows[0].Cells[0];$grid.Rows[0].Selected=$true;Load-Editor}
 return $shown
}
$read.Add_Click({
 if($script:writing -or $script:reading){return};if($script:dirty -and [Windows.Forms.MessageBox]::Show('Discard local edits and read the radio again?','Read Radio','YesNo') -ne 'Yes'){return}
 if(!$com.SelectedItem){[void][Windows.Forms.MessageBox]::Show('No COM port. Check your Prolific cable in Device Manager.');return}
 $candidate=$null
 try{
  $candidate=New-Object -TypeName IO.Ports.SerialPort -ArgumentList @([string]$com.SelectedItem,19200,[IO.Ports.Parity]::None,8,[IO.Ports.StopBits]::One)
  $candidate.Handshake='None';$candidate.ReadTimeout=100;$candidate.WriteTimeout=1000;$candidate.DtrEnable=$false;$candidate.RtsEnable=$false;$candidate.Open();$candidate.DiscardInBuffer()
  $script:serial=$candidate;$script:raw.SetLength(0);$script:stage=0;$script:blockCount=0;$script:first=$true;$script:reading=$true
  $script:lastByte=[DateTime]::UtcNow;$script:started=[DateTime]::UtcNow;$script:image=$null;$save.Enabled=$false;$write.Enabled=$false;$script:dirty=$false;$progress.Value=0;$grid.Rows.Clear();$search.Text=''
  $connection.Text='Reading '+$com.SelectedItem;Write-Log ('Read started on '+$com.SelectedItem+' at 19200 baud');$grid.ReadOnly=$true;$read.Enabled=$false;$refresh.Enabled=$false;$com.Enabled=$false;$cancel.Enabled=$true;$status.Text='Waiting for radio. Press BAND now. You have 60 seconds.'
 }catch{Write-Log $_.Exception.ToString();if($candidate){$candidate.Dispose()};Stop-Read ('Could not open cable: '+$_.Exception.Message)}
})
$cancel.Add_Click({if($script:writing){if([Windows.Forms.MessageBox]::Show('Interrupting upload may leave an incomplete radio image. Cancel anyway?','Cancel Write','YesNo') -ne 'Yes'){return};$script:writing=$false;$script:expectedWrite=$null;$write.Enabled=$true;$save.Enabled=$true;Stop-Read 'Write interrupted. Read radio again before proceeding.'}else{Stop-Read 'Read cancelled. Partial bytes discarded.';$script:raw.SetLength(0)}})
$save.Add_Click({
 if(!$grid.EndEdit()){return}
 if(!(Has-Image)){return};Update-Checksums $script:image
 $d=New-Object Windows.Forms.SaveFileDialog;$d.Filter='VX-7R binary clone image (*.img)|*.img';$d.FileName='VX7R-'+[DateTime]::Now.ToString('yyyyMMdd-HHmmss')+'.img'
 if($d.ShowDialog() -eq 'OK'){try{[IO.File]::WriteAllBytes($d.FileName,$script:image);$script:dirty=$false;$status.Text='Saved checksum-validated image: '+$d.FileName}catch{$status.Text='Save failed: '+$_.Exception.Message}};$d.Dispose()
})
$timer=New-Object Windows.Forms.Timer;$timer.Interval=25
$timer.Add_Tick({
 if($script:writing){Write-Tick;return}
 if(!$script:reading -or !$script:serial){return}
 try{
  $now=[DateTime]::UtcNow
  if($script:raw.Length -eq 0){if(($now-$script:started).TotalSeconds -gt 60){throw 'No response. Check CLONE mode, BAND, cable and COM port.'}}
  elseif(($now-$script:lastByte).TotalSeconds -gt 3){throw ('Transfer timed out at '+$script:raw.Length+' / 16211 bytes. Image not accepted.')}
  $budget=8192
  while($script:reading -and $script:serial.BytesToRead -gt 0 -and $budget -gt 0){
   $remaining=$script:lengths[$script:stage]-$script:blockCount
   $n=[Math]::Min([Math]::Min($remaining,$script:serial.BytesToRead),$budget)
   $data=New-Object byte[] $n;$got=$script:serial.Read($data,0,$n);if($got -le 0){break};$budget-=$got;$script:lastByte=[DateTime]::UtcNow
   $start=0
   if($script:first){if($data[0] -eq 6){$start=1};$script:first=$false}
   $used=$got-$start
   if($used -gt 0){$script:raw.Write($data,$start,$used);$script:blockCount+=$used}
   $progress.Value=[Math]::Min(16211,[int]$script:raw.Length);$status.Text='Reading '+$script:raw.Length+' / 16211 bytes...'
   if($script:blockCount -eq $script:lengths[$script:stage]){
    if($script:stage -lt 2){$ack=[byte[]]@(6);$script:serial.Write($ack,0,1);$script:stage++;$script:blockCount=0;$script:first=$true}
    else{
     $complete=$script:raw.ToArray();Check-Image $complete;$script:image=$complete;$script:original=[byte[]]$complete.Clone();Backup-Original $complete;$script:dirty=$false
     Stop-Read 'Read complete. 16211 bytes; all three checksums passed.'
     $shown=Show-Memories $complete;Write-Log ('Read succeeded: '+$shown+' memories; all checksums passed');$save.Enabled=$true;$write.Enabled=$true;$connection.Text='Read complete';$status.Text='Read complete: '+$shown+' used regular memories shown. All three checksums passed. Save Image to keep a backup.';if($script:expectedWrite){$same=$true;for($i=0;$i -lt 16211;$i++){if($complete[$i] -ne $script:expectedWrite[$i]){$same=$false;break}};if($same){$status.Text='Write verified: read-back matches the sent image exactly.';$script:expectedWrite=$null}else{$status.Text='Read-back differs from the sent image. Do not treat upload as verified.'}}
    }
   }
  }
 }catch{Write-Log $_.Exception.ToString();$script:image=$null;$save.Enabled=$false;Stop-Read ('Read failed: '+$_.Exception.Message);[void][Windows.Forms.MessageBox]::Show(($_.Exception.Message+"`r`nDetails saved in VX7R-error.log beside START.vbs."),'Radio read failed')}
})
$form.Add_FormClosing({param($sender,$event)if($script:writing -and [Windows.Forms.MessageBox]::Show('Upload is in progress. Interrupt and close?','Close','YesNo') -ne 'Yes'){$event.Cancel=$true;return};if($script:dirty -and [Windows.Forms.MessageBox]::Show('Close without saving local image edits?','Close','YesNo') -ne 'Yes'){$event.Cancel=$true;return};$script:writing=$false;$timer.Stop();Stop-Read '';$timer.Dispose();$script:raw.Dispose();$picture.Image.Dispose();if($radioPhoto.Image){$radioPhoto.Image.Dispose()}})
function Add-Overlay($control,$x,$y,$w,$h){$control.Font=$script:uiFont;$form.Controls.Add($control);$control.BringToFront();$script:controls+=,@($control,$x,$y,$w,$h)}
function Make-Action($text,$action,$x,$y,$w,$h){$b=New-Object Windows.Forms.Button;$b.Text=$text;$b.Tag=$action;$b.FlatStyle='Flat';$b.BackColor=[Drawing.Color]::FromArgb(15,55,92);$b.ForeColor=$ink;$b.FlatAppearance.BorderColor=[Drawing.Color]::FromArgb(60,93,120);$b.Add_Click({param($sender,$event)switch([string]$sender.Tag){'New'{New-Channel};'Delete'{Delete-Channel};'Apply'{Apply-Editor};'Import'{Import-Channels};'Export'{Export-Channels};'Banks'{Edit-Banks};'Open'{Open-Image};'Write'{Start-Write};'Read'{$read.PerformClick()};'Save'{$save.PerformClick()};'Refresh'{Refresh-Ports};'Device'{Start-Process devmgmt.msc};'Beep'{Edit-Beep};'Snapshot'{Show-DisplaySnapshot};'ScanFlags'{Edit-ScanMemories};'Help'{Show-Help}}});Add-Overlay $b $x $y $w $h;return $b}
$write=Make-Action 'Write Radio' 'Write' 548 731 140 46;$write.Enabled=$false
[void](Make-Action 'New' 'New' 700 731 84 46);[void](Make-Action 'Apply Edit' 'Apply' 795 731 86 46);[void](Make-Action 'Delete' 'Delete' 892 731 85 46);[void](Make-Action 'Import CSV' 'Import' 988 731 101 46)
$save.Text='Save Image';[void](Make-Action 'Export CSV' 'Export' 1218 737 104 33);[void](Make-Action 'Open Image' 'Open' 1328 737 110 33)
$cancel.Text='Cancel';$cancel.BackColor=[Drawing.Color]::FromArgb(92,40,35)
$script:controls= @($script:controls | Where-Object { $_[0] -ne $cancel });$cancel.Bounds=New-Object Drawing.Rectangle(710,945,94,30);$script:controls+=,@($cancel,710,945,94,30)
$heading=New-Object Windows.Forms.Label;$heading.Text='Memory Channels 1–450  |  Working image';$heading.BackColor=$panelColor;$heading.ForeColor=$ink;Add-Overlay $heading 402 358 465 37
$search=New-Object Windows.Forms.TextBox;$search.BackColor=$panelColor;$search.ForeColor=$ink;Add-Overlay $search 1019 362 188 29
$search.Add_TextChanged({$grid.CurrentCell=$null;foreach($row in $grid.Rows){$needle=$search.Text.ToLowerInvariant();$hay=([string]$row.Cells[0].Value+' '+[string]$row.Cells[1].Value+' '+[string]$row.Cells[3].Value).ToLowerInvariant();$row.Visible=(!$needle -or $hay.Contains($needle))}})
$channelLabel=New-Object Windows.Forms.Label;$channelLabel.Text='Select a channel';$channelLabel.BackColor=$panelColor;$channelLabel.ForeColor=$ink;Add-Overlay $channelLabel 1347 392 168 29
$script:fields=@{}
$positions=@(@('Frequency',426),@('Mode',460),@('Name',493),@('Duplex',526),@('ToneMode',560),@('Tone',593),@('Step',626),@('Power',659),@('DCS',692),@('Offset',786),@('Skip',821))
foreach($p in $positions){$key=$p[0];$choices=$null
 switch($key){'Mode'{$choices=$script:modes};'Duplex'{$choices=$script:duplexes};'ToneMode'{$choices=@('Off','Tone','TSQL','DTCS','Cross (preserve)')};'Tone'{$choices=$script:tones};'Step'{$choices=$script:steps};'Power'{$choices=@(0,1,2,3)};'DCS'{$choices=$script:dcs};'Skip'{$choices=@('','S','P')}}
 if($null -ne $choices){$field=New-Object Windows.Forms.ComboBox;$field.DropDownStyle='DropDownList';$field.FlatStyle='Flat';foreach($choice in $choices){[void]$field.Items.Add([string]$choice)};if($field.Items.Count){$field.SelectedIndex=0}}
 else{$field=New-Object Windows.Forms.TextBox}
 $field.BackColor=$panelColor;$field.ForeColor=$ink;$script:fields[$key]=$field;Add-Overlay $field 1347 $p[1] 168 29
 $label=New-Object Windows.Forms.Label;$label.Text=$key;$label.BackColor=$panelColor;$label.ForeColor=$ink;Add-Overlay $label 1228 $p[1] 115 29
}
$editorCover=New-Object Windows.Forms.Label;$editorCover.Text='Editor: offset is MHz magnitude; Duplex sets sign.';$editorCover.BackColor=$panelColor;$editorCover.ForeColor=$ink;Add-Overlay $editorCover 1046 866 476 27
$grid.Add_SelectionChanged({Load-Editor})
[void](Make-Action 'Banks' 'Banks' 540 313 105 39);[void](Make-Action 'Clone' 'Read' 1321 313 95 39)
$script:tips=New-Object Windows.Forms.ToolTip
foreach($p in @(@('VFO',653,95),@('Scan',752,88),@('Set Mode',844,134),@('DTMF',981,98),@('APRS / GPS',1082,139),@('Misc',1225,93))){$b=New-Object Windows.Forms.Button;$b.Text=$p[0];$b.Enabled=$false;$b.FlatStyle='Flat';$b.BackColor=$panelColor;$b.ForeColor=$ink;Add-Overlay $b $p[1] 313 $p[2] 39}
$settingsCover=New-Object Windows.Forms.Label;$settingsCover.Text="Memory clone controls are available above.`r`nLive VFO tuning, scanning and keypad/PTT are unavailable through clone mode. Settings: KEY BEEP is editable. Other Set Mode/DTMF items are not mapped yet.`r`nPower codes: 0=L1 50mW, 1=L2 1W, 2=L3 2.5W, 3=Hi 5W (220 MHz differs).";$settingsCover.BackColor=$panelColor;$settingsCover.ForeColor=$ink;Add-Overlay $settingsCover 16 809 675 178
$script:fields['Frequency'].Text='145.500';$script:fields['Offset'].Text='0.000'
foreach($buttonInfo in @(@('FM',1275,117,'FM'),@('AM',1275,150,'AM'),@('WFM',1438,117,'WFM'))){$b=New-Object Windows.Forms.Button;$b.Text=$buttonInfo[0];$b.Tag=$buttonInfo[3];$b.FlatStyle='Flat';$b.ForeColor=$ink;$b.BackColor=[Drawing.Color]::FromArgb(15,55,92);$b.Add_Click({param($sender,$event)if(Has-Image){$script:fields['Mode'].Text=[string]$sender.Tag;Apply-Editor}});Add-Overlay $b $buttonInfo[1] $buttonInfo[2] 76 29}
foreach($p in @(@('NFM',1357,117),@('NAM',1357,150),@('SSB',1438,150),@('CW',1275,184),@('CWR',1357,184),@('DATA',1438,184))){$b=New-Object Windows.Forms.Button;$b.Text=$p[0];$b.Enabled=$false;$b.BackColor=$panelColor;$b.FlatStyle='Flat';Add-Overlay $b $p[1] $p[2] 76 29}
foreach($p in @(@('H 5W',1275,3),@('M 2.5W',1357,2),@('L 1W',1438,1))){$b=New-Object Windows.Forms.Button;$b.Text=$p[0];$b.Tag=$p[2];$b.BackColor=[Drawing.Color]::FromArgb(15,55,92);$b.ForeColor=$ink;$b.FlatStyle='Flat';$b.Add_Click({param($sender,$event)if(Has-Image){$script:fields['Power'].Text=[string]$sender.Tag;Apply-Editor}});Add-Overlay $b $p[1] 258 76 31}
function Show-Help{[void][Windows.Forms.MessageBox]::Show("Read your own radio first. Select a row, edit fields, then Apply Edit. You can also double-click table cells or press F2.`r`nNew/Delete/Import change only the working image. Save Image keeps it on this PC.`r`nWrite Radio saves the original in Backups, prompts for CLONE WAIT and sends the working image. Read Radio afterwards to verify.`r`nBanks assigns the selected memory to MG1–MG9. Export/Import CSV uses this app's format.`r`nLive VFO/PTT/scan are unavailable. Settings includes KEY BEEP. Other Set Mode and DTMF items are not mapped yet.",'Help')}
function Show-Menu($name,$point){
 $menu=New-Object Windows.Forms.ContextMenuStrip
 $entries=@()
 switch($name){'File'{$entries=@(@('Open Image','Open'),@('Save Image','Save'),@('Import CSV','Import'),@('Export CSV','Export'))};'Radio'{$entries=@(@('Read Radio','Read'),@('Write Radio','Write'),@('Refresh COM','Refresh'))};'Memory'{$entries=@(@('New channel','New'),@('Apply editor','Apply'),@('Delete channel','Delete'),@('Edit banks','Banks'))};'VFO'{$entries=@(@('View saved main/sub display','Snapshot'),@('Refresh by reading radio','Read'))};'Scan'{$entries=@(@('Edit memory skip / prefer flags','ScanFlags'))};'Settings'{$entries=@(@('Basic #9: KEY BEEP - ON/OFF','Beep'))};'Tools'{$entries=@(@('Refresh COM','Refresh'),@('Device Manager','Device'),@('Help','Help'))};default{$entries=@(@('Supported controls and limitations','Help'))}}
 foreach($entry in $entries){$item=New-Object Windows.Forms.ToolStripMenuItem;$item.Text=$entry[0];$item.Tag=$entry[1];$item.Add_Click({param($sender,$event)switch([string]$sender.Tag){'Open'{Open-Image};'Save'{$save.PerformClick()};'Import'{Import-Channels};'Export'{Export-Channels};'Read'{$read.PerformClick()};'Write'{Start-Write};'Refresh'{Refresh-Ports};'New'{New-Channel};'Apply'{Apply-Editor};'Delete'{Delete-Channel};'Banks'{Edit-Banks};'Device'{Start-Process devmgmt.msc};'Beep'{Edit-Beep};'Snapshot'{Show-DisplaySnapshot};'ScanFlags'{Edit-ScanMemories};'Help'{Show-Help}}});[void]$menu.Items.Add($item)}
 $menu.Show($picture,$point)
}
$picture.Add_MouseClick({param($sender,$event)
 $scale=$picture.ClientSize.Width/1536.0;$x=$event.X/$scale;$y=$event.Y/$scale
 if($y -ge 35 -and $y -le 70){$name='Help';if($x -lt 60){$name='File'}elseif($x -lt 125){$name='Radio'}elseif($x -lt 204){$name='Memory'}elseif($x -ge 418 -and $x -lt 482){$name='Tools'};Show-Menu $name $event.Location}
 elseif($x -lt 380 -and $y -gt 420){$status.Text='The pictured radio keypad is artwork; remote keypad/PTT is not supported by the VX-7R clone cable.'}
})
$script:controls=@($script:controls | ForEach-Object {if($_[0] -eq $instructions){,@($instructions,1046,900,476,83)}else{,$_}})
$transferCover=New-Object Windows.Forms.Label;$transferCover.Text="Clone transfer status`r`nRead: CLONE, click Read Radio, press BAND.`r`nWrite: follow CLONE WAIT prompt.`r`nRead back after sending to verify.";$transferCover.BackColor=$panelColor;$transferCover.ForeColor=$ink;Add-Overlay $transferCover 710 809 313 124
$cancel.BringToFront()
$instructions.Text="1. Read your radio; original is backed up.`r`n2. Edit selected channel and Apply Edit.`r`n3. Save Image or Write Radio.`r`n4. Read Radio after writing to verify.`r`nClone-only: no live tuning/PTT. Top LCDs show the saved VFO snapshot."
Resize-Dashboard

$script:refreshingGrid=$false
$grid.ReadOnly=$false;$grid.EditMode='EditOnKeystrokeOrF2';$grid.Columns[0].ReadOnly=$true
$grid.ColumnHeadersHeight=38;$grid.ColumnHeadersHeightSizeMode='DisableResizing'
$grid.ColumnHeadersDefaultCellStyle.WrapMode='True'
$grid.Columns[0].MinimumWidth=66;$grid.Columns[1].MinimumWidth=125;$grid.Columns[2].MinimumWidth=65;$grid.Columns[3].MinimumWidth=90;$grid.Columns[4].MinimumWidth=65;$grid.Columns[5].MinimumWidth=110;$grid.Columns[6].MinimumWidth=55
function Commit-GridCell($rowIndex,$columnIndex,$value,$validateOnly){
 if(!$script:image -or $script:reading -or $script:writing){throw 'Read a radio image first and wait for the transfer to finish.'}
 if($rowIndex -lt 0 -or $columnIndex -lt 1){return}
 $n=[int]$grid.Rows[$rowIndex].Cells[0].Value
 $item=Read-Channel $script:image $n
 $property=@('Channel','Frequency','Mode','Name','Duplex','Offset','Skip')[$columnIndex]
 if([string]$item.$property -eq [string]$value){return}
 $item.$property=[string]$value;$copy=[byte[]]$script:image.Clone();Write-Channel $copy $item;Update-Checksums $copy;Check-Image $copy
 if(!$validateOnly){$script:image=$copy;Mark-Dirty;Load-Editor}
}
$grid.Add_CellValidating({param($sender,$event)
 if($script:refreshingGrid -or $event.RowIndex -lt 0 -or $event.ColumnIndex -lt 1){return}
 try{Commit-GridCell $event.RowIndex $event.ColumnIndex $event.FormattedValue $true;$grid.Rows[$event.RowIndex].ErrorText=''}catch{$event.Cancel=$true;$grid.Rows[$event.RowIndex].ErrorText=$_.Exception.Message;$status.Text='Edit rejected: '+$_.Exception.Message}
})
$grid.Add_CellEndEdit({param($sender,$event)
 if($script:refreshingGrid -or $event.RowIndex -lt 0 -or $event.ColumnIndex -lt 1){return}
 try{Commit-GridCell $event.RowIndex $event.ColumnIndex $grid.Rows[$event.RowIndex].Cells[$event.ColumnIndex].Value $false;$grid.Rows[$event.RowIndex].ErrorText=''}catch{$status.Text='Edit failed: '+$_.Exception.Message;Write-Log $_.Exception.ToString()}
})
$grid.Add_CellClick({param($sender,$event)if($event.RowIndex -ge 0){$grid.ClearSelection();$grid.Rows[$event.RowIndex].Selected=$true;Load-Editor}})
$grid.Add_CurrentCellChanged({if(!$script:refreshingGrid){Load-Editor}})
$grid.Add_CellDoubleClick({param($sender,$event)if($event.RowIndex -ge 0 -and $event.ColumnIndex -gt 0 -and !$grid.ReadOnly){[void]$grid.BeginEdit($true)}})
$grid.Add_DataError({param($sender,$event)$event.ThrowException=$false;$status.Text='Invalid table value; press Esc to undo the cell edit.'})
$script:tips.SetToolTip($grid,'Select a row to load the side editor. Double-click a cell or press F2 to edit directly. Enter commits; Esc cancels.')
$applyTip='Edit fields, then Apply Edit. Or edit table cells directly with F2.'
$script:tips.SetToolTip($channelLabel,$applyTip)
# Replace the imagined radio with the user's actual silver VX-7R photograph.
$radioPhoto=New-Object Windows.Forms.PictureBox;$radioPhoto.Image=[Drawing.Image]::FromFile((Join-Path $PSScriptRoot 'vx7r-silver.png'));$radioPhoto.SizeMode='Zoom';$radioPhoto.BackColor=$panelColor
Add-Overlay $radioPhoto 0 71 379 718
$script:tips.SetToolTip($radioPhoto,'Actual silver Yaesu VX-7R photo supplied by you. The displayed frequencies are part of the photo.')
# Actual menu strip replaces the static lettering, with the same full names.
$topMenu=New-Object Windows.Forms.MenuStrip;$topMenu.Dock='None';$topMenu.AutoSize=$false;$topMenu.BackColor=$panelColor;$topMenu.ForeColor=$ink;$topMenu.GripStyle='Hidden'
foreach($name in @('File','Radio','Memory','VFO','Scan','Settings','Tools','Help')){
 $entry=New-Object Windows.Forms.ToolStripMenuItem;$entry.Text=$name;$entry.Tag=$name;$entry.ForeColor=$ink
 $entry.Add_Click({param($sender,$event)if($sender.Tag -eq 'Help'){Show-Help}else{Show-Menu ([string]$sender.Tag) (New-Object Drawing.Point(5,[int](70*$picture.ClientSize.Width/1536.0)))}})
 [void]$topMenu.Items.Add($entry)
}
Add-Overlay $topMenu 0 34 570 37
Resize-Dashboard

# Main/sub VFO BCD locations verified against two user-supplied clone images.
# 0x5A2 / 0x5D8 match redundant copies at 0x622 / 0x658 respectively.
function Update-VfoDisplays($data){
 if(!$script:vfoDisplays){return}
 for($band=0;$band -lt 2;$band++){
  $base=@(0x592,0x5C8)[$band];$duplicate=$base+0x80
  try{
   $khz=Get-Bcd $data ($base+16);$copy=Get-Bcd $data ($duplicate+16)
   if($khz -ne $copy){throw 'Display copies differ'}
   if($khz -lt 500 -or $khz -gt 999000){throw 'Frequency out of range'}
   $name=''
   for($j=0;$j -lt 8;$j++){
    $v=[int]$data[$base+24+$j]
    if($v -ne [int]$data[$duplicate+24+$j]){throw 'Name copies differ'}
    if($v -eq 255){break}
    if($v -ge $script:charset.Length){throw 'Unknown name character'}
    $name+=$script:charset[$v]
   }
   $name=$name.TrimEnd();$detail='VFO snapshot'
   $state=[int]$data[$base+2];$stateCopy=[int]$data[$duplicate+2]
   if($state -eq 1 -and $stateCopy -eq 1){
    $index=([int]$data[$base+38] -shl 8) -bor [int]$data[$base+39]
    $indexCopy=([int]$data[$duplicate+38] -shl 8) -bor [int]$data[$duplicate+39]
    $number=$index+1;$detail='Memory snapshot'
    if($index -eq $indexCopy -and $number -ge 1 -and $number -le 450 -and ((Get-Flag $data $number) -band 3) -eq 3){
     $memory=Read-Channel $data $number
     if((Get-Bcd $data (0x1322+$index*22+2)) -eq $khz -and $memory.Name -eq $name){$detail=('CH '+$number.ToString('000')+' | '+$memory.Mode+' | Snapshot')}
    }
   }
   $script:vfoDisplays[$band].Text=($khz/1000.0).ToString('F6',[Globalization.CultureInfo]::InvariantCulture)
   if($name){$script:vfoNotes[$band].Text=$name+"`r`n"+$detail}else{$script:vfoNotes[$band].Text='MHz | '+$detail}
  }catch{$script:vfoDisplays[$band].Text='Unavailable';$script:vfoNotes[$band].Text='Display snapshot not verified'}
 }
}
$script:vfoDisplays=@();$script:vfoNotes=@()
foreach($x in @(420,858)){
 $lcdPanel=New-Object Windows.Forms.Panel;$lcdPanel.BackColor=[Drawing.Color]::FromArgb(185,205,154)
 $digits=New-Object Windows.Forms.Label;$digits.Dock='Fill';$digits.Text='---.------';$digits.TextAlign='MiddleCenter';$digits.BackColor=$lcdPanel.BackColor;$digits.ForeColor=[Drawing.Color]::FromArgb(15,25,16)
 $digits.Font=New-Object Drawing.Font('Consolas',24,[Drawing.FontStyle]::Bold)
 $note=New-Object Windows.Forms.Label;$note.Dock='Bottom';$note.Height=57;$note.Text='Read Radio to load snapshot';$note.TextAlign='MiddleCenter';$note.BackColor=$lcdPanel.BackColor;$note.ForeColor=$digits.ForeColor;$note.Font=New-Object Drawing.Font('Segoe UI',11,[Drawing.FontStyle]::Regular)
 $lcdPanel.Controls.Add($digits);$lcdPanel.Controls.Add($note)
 Add-Overlay $lcdPanel $x 128 375 157
 # Child digit font stays alive; do not dispose it during resizing.
 $digits.Font=New-Object Drawing.Font('Consolas',24,[Drawing.FontStyle]::Bold)
 $script:vfoDisplays+=,$digits;$script:vfoNotes+=,$note
}
Resize-Dashboard

# KEY BEEP: 0x695 bit 0x04. User-confirmed ON->OFF capture: AC->A8.
function Edit-Beep{
 if(!(Has-Image)){return}
 $dialog=New-Object Windows.Forms.Form;$dialog.Text='Settings - Basic Setup #9 KEY BEEP';$dialog.Size=New-Object Drawing.Size(460,230);$dialog.StartPosition='CenterParent';$dialog.FormBorderStyle='FixedDialog';$dialog.MaximizeBox=$false;$dialog.MinimizeBox=$false
 $dialog.BackColor=$panelColor;$dialog.ForeColor=$ink;$dialog.Font=$script:uiFont
 $label=New-Object Windows.Forms.Label;$label.Text='KEY BEEP - keypad sound';$label.Location=New-Object Drawing.Point(18,15);$label.AutoSize=$true;$dialog.Controls.Add($label)
 $toggle=New-Object Windows.Forms.CheckBox;$toggle.Text='ON (unchecked = OFF)';$toggle.AutoSize=$true;$toggle.Location=New-Object Drawing.Point(20,48);$toggle.Checked=(([int]$script:image[0x695] -band 4) -ne 0);$dialog.Controls.Add($toggle)
 $note=New-Object Windows.Forms.Label;$note.Text="This changes the working image only.`r`nUse Write Radio afterwards, then Read Radio to verify.";$note.Location=New-Object Drawing.Point(18,83);$note.Size=New-Object Drawing.Size(410,48);$dialog.Controls.Add($note)
 $apply=New-Object Windows.Forms.Button;$apply.Text='Apply';$apply.Location=New-Object Drawing.Point(230,145);$apply.DialogResult='OK';$dialog.Controls.Add($apply)
 $dismiss=New-Object Windows.Forms.Button;$dismiss.Text='Cancel';$dismiss.Location=New-Object Drawing.Point(320,145);$dismiss.DialogResult='Cancel';$dialog.Controls.Add($dismiss);$dialog.AcceptButton=$apply;$dialog.CancelButton=$dismiss
 if($dialog.ShowDialog($form) -eq 'OK'){
  try{
   $copy=[byte[]]$script:image.Clone();$old=[int]$copy[0x695]
   if($toggle.Checked){$copy[0x695]=[byte]($old -bor 4)}else{$copy[0x695]=[byte]($old -band 251)}
   if([int]$copy[0x695] -ne $old){Update-Checksums $copy;Check-Image $copy;$script:image=$copy;Mark-Dirty;Write-Log ('KEY BEEP edited locally: '+$toggle.Checked)}
   $value='OFF';if($toggle.Checked){$value='ON'};$status.Text='KEY BEEP = '+$value+' in working image. Write Radio applies it to the radio.'
  }catch{Write-Log $_.Exception.ToString();[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Setting edit failed')}
 }
 $dialog.Dispose()
}
[void](Make-Action 'Set Mode' 'Beep' 844 313 134 39)
Resize-Dashboard

function Show-DisplaySnapshot{
 if(!(Has-Image)){return}
 $dialog=New-Object Windows.Forms.Form;$dialog.Text='VFO / Memory - saved radio display';$dialog.Size=New-Object Drawing.Size(520,285);$dialog.StartPosition='CenterParent';$dialog.BackColor=$panelColor;$dialog.ForeColor=$ink;$dialog.Font=$script:uiFont
 $text=New-Object Windows.Forms.Label;$text.Dock='Fill';$text.Padding=New-Object Windows.Forms.Padding(15);$text.Text="MAIN`r`n"+$script:vfoDisplays[0].Text+' MHz'+"`r`n"+$script:vfoNotes[0].Text+"`r`n`r`nSUB`r`n"+$script:vfoDisplays[1].Text+' MHz'+"`r`n"+$script:vfoNotes[1].Text;$dialog.Controls.Add($text)
 $footer=New-Object Windows.Forms.Label;$footer.Dock='Bottom';$footer.Height=38;$footer.Text='Saved clone snapshot. Read Radio again to refresh; no live tuning.';$dialog.Controls.Add($footer)
 $buttons=New-Object Windows.Forms.FlowLayoutPanel;$buttons.Dock='Bottom';$buttons.Height=40
 $refreshSnapshot=New-Object Windows.Forms.Button;$refreshSnapshot.Text='Read Radio';$refreshSnapshot.AutoSize=$true;$refreshSnapshot.DialogResult='Retry'
 $close=New-Object Windows.Forms.Button;$close.Text='Close';$close.DialogResult='OK';$buttons.Controls.AddRange(@($refreshSnapshot,$close));$dialog.Controls.Add($buttons)
 $result=$dialog.ShowDialog($form);$dialog.Dispose();if($result -eq 'Retry'){$read.PerformClick()}
}
function Edit-ScanMemories{
 if(!(Has-Image)){return}
 $dialog=New-Object Windows.Forms.Form;$dialog.Text='Scan - memory skip / preferential flags';$dialog.Size=New-Object Drawing.Size(720,590);$dialog.StartPosition='CenterParent';$dialog.BackColor=$panelColor;$dialog.ForeColor=$ink;$dialog.Font=$script:uiFont
 $info=New-Object Windows.Forms.Label;$info.Dock='Top';$info.Height=52;$info.Text="Normal = included; Skip = omitted; Prefer = preferential flag.`r`nApply changes the image. Write Radio applies it to the radio. This does not start a live scan.";$dialog.Controls.Add($info)
 $table=New-Object Windows.Forms.DataGridView;$table.Dock='Fill';$table.AllowUserToAddRows=$false;$table.AllowUserToDeleteRows=$false;$table.RowHeadersVisible=$false;$table.AutoSizeColumnsMode='Fill';$table.BackgroundColor=$panelColor
 foreach($name in @('Channel','Frequency','Name')){$index=$table.Columns.Add($name,$name);$table.Columns[$index].ReadOnly=$true}
 $choice=New-Object Windows.Forms.DataGridViewComboBoxColumn;$choice.Name='Scan';$choice.HeaderText='Scan flag';[void]$choice.Items.Add('Normal');[void]$choice.Items.Add('Skip');[void]$choice.Items.Add('Prefer');[void]$table.Columns.Add($choice)
 for($n=1;$n -le 450;$n++){
  $flags=Get-Flag $script:image $n;if(($flags -band 3) -ne 3){continue};$item=Read-Channel $script:image $n;$mode='Normal';if($item.Skip -eq 'S'){$mode='Skip'}elseif($item.Skip -eq 'P'){$mode='Prefer'}
  [void]$table.Rows.Add([object[]]@($n,$item.Frequency,$item.Name,$mode))
 }
 $dialog.Controls.Add($table);$table.BringToFront()
 $buttons=New-Object Windows.Forms.FlowLayoutPanel;$buttons.Dock='Bottom';$buttons.Height=40
 $apply=New-Object Windows.Forms.Button;$apply.Text='Apply';$apply.DialogResult='OK'
 $cancelScan=New-Object Windows.Forms.Button;$cancelScan.Text='Cancel';$cancelScan.DialogResult='Cancel';$buttons.Controls.AddRange(@($apply,$cancelScan));$dialog.Controls.Add($buttons);$buttons.BringToFront();$dialog.AcceptButton=$apply;$dialog.CancelButton=$cancelScan
 $layout=New-Object Windows.Forms.TableLayoutPanel;$layout.Dock='Fill';$layout.ColumnCount=1;$layout.RowCount=3
 [void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',52)));[void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',100)));[void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',40)))
 $dialog.Controls.Clear();$info.Dock='Fill';$table.Dock='Fill';$buttons.Dock='Fill';$layout.Controls.Add($info,0,0);$layout.Controls.Add($table,0,1);$layout.Controls.Add($buttons,0,2);$dialog.Controls.Add($layout)
 if($dialog.ShowDialog($form) -eq 'OK'){
  try{
   [void]$table.EndEdit();$copy=[byte[]]$script:image.Clone();$changed=$false
   foreach($row in $table.Rows){$n=[int]$row.Cells[0].Value;$old=Get-Flag $copy $n;$bits=$old -band 3;switch([string]$row.Cells[3].Value){'Normal'{};'Skip'{$bits=$bits -bor 4};'Prefer'{$bits=$bits -bor 8};default{throw 'Invalid scan flag.'}};if($bits -ne $old){Set-Flag $copy $n $bits;$changed=$true}}
   if($changed){Update-Checksums $copy;Check-Image $copy;$selected=Selected-Number;$script:image=$copy;[void](Refresh-MemoryGrid $selected);Mark-Dirty;$status.Text='Scan flags updated locally. Write Radio to apply.'}else{$status.Text='Scan flags unchanged.'}
  }catch{Write-Log $_.Exception.ToString();[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Scan edit failed')}
 }
 $dialog.Dispose()
}
[void](Make-Action 'VFO' 'Snapshot' 653 313 95 39)
[void](Make-Action 'Scan' 'ScanFlags' 752 313 88 39)
Resize-Dashboard

Write-Log 'Application opened.';Refresh-Ports;$timer.Start();[void]$form.ShowDialog();$form.Dispose()

} catch {
 $message=$_.Exception.ToString()
 try {Add-Content -LiteralPath (Join-Path $PSScriptRoot 'VX7R-error.log') -Value $message -Encoding UTF8}catch{}
 Add-Type -AssemblyName System.Windows.Forms
 [void][Windows.Forms.MessageBox]::Show($message,'VX-7R startup error')
}
