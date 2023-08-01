Start-Process 'komorebi.exe' -ArgumentList '--config="C:\Users\settw\komorebi.json"' -WindowStyle hidden

if (!(Get-Process whkd -ErrorAction SilentlyContinue))
{
  Start-Process whkd -WindowStyle hidden
}
