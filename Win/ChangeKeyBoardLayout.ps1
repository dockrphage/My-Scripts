# Prompt the user to select a keyboard layout
# This is handy when using a UK laptop in combination with an external keyboard of US layout
$choice = Read-Host "Enter the keyboard layout you want to use (US or UK)"

# Process the user's input
switch ($choice.ToUpper()) {
    "US" { 
        Set-WinUserLanguageList -LanguageList en-US -Force
        Write-Host "Keyboard layout changed to US (en-US)" -ForegroundColor Green
    }
    "UK" { 
        Set-WinUserLanguageList -LanguageList en-GB -Force
        Write-Host "Keyboard layout changed to UK (en-GB)" -ForegroundColor Green				
    }
    default {
        Write-Host "Invalid input. Please enter either 'US' or 'UK'." -ForegroundColor Red
    }
}
