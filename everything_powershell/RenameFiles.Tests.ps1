# Unit Tests for REPWSH-Organization Function
# Requires Pester 5.x (Install: Install-Module -Name Pester -Force -SkipPublisherCheck)

BeforeAll {
    Context "Screaming Snake Case Conversion - Files" {
        
        It "Converts lowercase to SCREAMING_SNAKE_CASE" {
            New-TestFile -Path $testPath -Name "myfile.txt"
            REPWSH-Organization -ScreamingSnake -Path $testPath
            
            Test-Path (Join-Path $testPath "MYFILE.TXT") | Should -Be $true
        }
        
        It "Converts PascalCase to SCREAMING_SNAKE_CASE" {
            New-TestFile -Path $testPath -Name "MyFileName.txt"
            REPWSH-Organization -ScreamingSnake -Path $testPath
            
            Test-Path (Join-Path $testPath "MY_FILE_NAME.TXT") | Should -Be $true
        }
        
        It "Converts camelCase to SCREAMING_SNAKE_CASE" {
            New-TestFile -Path $testPath -Name "myFileName.txt"
            REPWSH-Organization -ScreamingSnake -Path $testPath
            
            Test-Path (Join-Path $testPath "MY_FILE_NAME.TXT") | Should -Be $true
        }
        
        It "Converts spaces to SCREAMING_SNAKE_CASE" {
            New-TestFile -Path $testPath -Name "My File Name.txt"
            REPWSH-Organization -ScreamingSnake -Path $testPath
            
            Test-Path (Join-Path $testPath "MY_FILE_NAME.TXT") | Should -Be $true
        }
        
        It "Preserves already correct SCREAMING_SNAKE_CASE names" {
            New-TestFile -Path $testPath -Name "ALREADY_SCREAMING.TXT"
            REPWSH-Organization -ScreamingSnake -Path $testPath
            
            Test-Path (Join-Path $testPath "ALREADY_SCREAMING.TXT") | Should -Be $true
        }
        
        It "Converts snake_case to SCREAMING_SNAKE_CASE" {
            New-TestFile -Path $testPath -Name "my_file_name.txt"
            REPWSH-Organization -ScreamingSnake -Path $testPath
            
            Test-Path (Join-Path $testPath "MY_FILE_NAME.TXT") | Should -Be $true
        }
    }
    # Import the function to test
    # Adjust the path to your script file
    . "$PSScriptRoot\RenameFiles.ps1"
    
    # Create test helper functions
    function New-TestFile {
        param(
            [string]$Path,
            [string]$Name
        )
        $fullPath = Join-Path $Path $Name
        New-Item -Path $fullPath -ItemType File -Force | Out-Null
        return $fullPath
    }
    
    function New-TestDirectory {
        param(
            [string]$Path,
            [string]$Name
        )
        $fullPath = Join-Path $Path $Name
        New-Item -Path $fullPath -ItemType Directory -Force | Out-Null
        return $fullPath
    }
}

Describe "REPWSH-Organization" {
    
    BeforeEach {
        # Create a temporary test directory
        $script:testPath = Join-Path $TestDrive "RenameTest_$(Get-Random)"
        New-Item -Path $script:testPath -ItemType Directory -Force | Out-Null
    }
    
    Context "Snake Case Conversion - Files" {
        
        It "Converts uppercase with underscores to lowercase" {
            New-TestFile -Path $testPath -Name "MKEY.py"
            REPWSH-Organization -Snake -Path $testPath
            
            Test-Path (Join-Path $testPath "mkey.py") | Should -Be $true
        }
        
        It "Converts uppercase with underscores and multiple words" {
            New-TestFile -Path $testPath -Name "UV_CHECKER.png"
            REPWSH-Organization -Snake -Path $testPath
            
            Test-Path (Join-Path $testPath "uv_checker.png") | Should -Be $true
        }
        
        It "Converts PascalCase to snake_case" {
            New-TestFile -Path $testPath -Name "MyFileName.txt"
            REPWSH-Organization -Snake -Path $testPath
            
            Test-Path (Join-Path $testPath "my_file_name.txt") | Should -Be $true
        }
        
        It "Converts camelCase to snake_case" {
            New-TestFile -Path $testPath -Name "myFileName.txt"
            REPWSH-Organization -Snake -Path $testPath
            
            Test-Path (Join-Path $testPath "my_file_name.txt") | Should -Be $true
        }
        
        It "Converts spaces to underscores" {
            New-TestFile -Path $testPath -Name "My File Name.txt"
            REPWSH-Organization -Snake -Path $testPath
            
            Test-Path (Join-Path $testPath "my_file_name.txt") | Should -Be $true
        }
        
        It "Converts special characters to underscores" {
            New-TestFile -Path $testPath -Name "My-File@Name!.txt"
            REPWSH-Organization -Snake -Path $testPath
            
            Test-Path (Join-Path $testPath "my_file_name.txt") | Should -Be $true
        }
        
        It "Handles multiple consecutive capitals" {
            New-TestFile -Path $testPath -Name "HTTPResponse.txt"
            REPWSH-Organization -Snake -Path $testPath
            
            Test-Path (Join-Path $testPath "http_response.txt") | Should -Be $true
        }
        
        It "Preserves already correct snake_case names" {
            New-TestFile -Path $testPath -Name "already_snake_case.txt"
            REPWSH-Organization -Snake -Path $testPath
            
            Test-Path (Join-Path $testPath "already_snake_case.txt") | Should -Be $true
        }
        
        It "Converts file extension to lowercase" {
            New-TestFile -Path $testPath -Name "MyFile.TXT"
            REPWSH-Organization -Snake -Path $testPath
            
            Test-Path (Join-Path $testPath "my_file.txt") | Should -Be $true
        }
    }
    
    Context "Camel Case Conversion - Files" {
        
        It "Converts snake_case to camelCase" {
            New-TestFile -Path $testPath -Name "my_file_name.txt"
            REPWSH-Organization -Camel -Path $testPath
            
            Test-Path (Join-Path $testPath "myFileName.txt") | Should -Be $true
        }
        
        It "Converts spaces to camelCase" {
            New-TestFile -Path $testPath -Name "My File Name.txt"
            REPWSH-Organization -Camel -Path $testPath
            
            Test-Path (Join-Path $testPath "myFileName.txt") | Should -Be $true
        }
        
        It "Converts PascalCase to camelCase" {
            New-TestFile -Path $testPath -Name "MyFileName.txt"
            REPWSH-Organization -Camel -Path $testPath
            
            Test-Path (Join-Path $testPath "myFileName.txt") | Should -Be $true
        }
        
        It "Converts uppercase with underscores to camelCase" {
            New-TestFile -Path $testPath -Name "MY_FILE_NAME.txt"
            REPWSH-Organization -Camel -Path $testPath
            
            Test-Path (Join-Path $testPath "myFileName.txt") | Should -Be $true
        }
        
        It "Converts special characters to camelCase" {
            New-TestFile -Path $testPath -Name "my-file@name.txt"
            REPWSH-Organization -Camel -Path $testPath
            
            Test-Path (Join-Path $testPath "myFileName.txt") | Should -Be $true
        }
        
        It "Preserves already correct camelCase names" {
            New-TestFile -Path $testPath -Name "alreadyCamelCase.txt"
            REPWSH-Organization -Camel -Path $testPath
            
            Test-Path (Join-Path $testPath "alreadyCamelCase.txt") | Should -Be $true
        }
    }
    
    Context "Directory Handling" {
        
        It "Does not rename directories without -Dir switch" {
            New-TestDirectory -Path $testPath -Name "MyFolder"
            REPWSH-Organization -Snake -Path $testPath
            
            Test-Path (Join-Path $testPath "MyFolder") | Should -Be $true
            Test-Path (Join-Path $testPath "my_folder") | Should -Be $false
        }
        
        It "Renames directories with -Dir switch (snake_case)" {
            New-TestDirectory -Path $testPath -Name "MyFolder"
            REPWSH-Organization -Snake -Dir -Path $testPath
            
            Test-Path (Join-Path $testPath "my_folder") | Should -Be $true
            Test-Path (Join-Path $testPath "MyFolder") | Should -Be $false
        }
        
        It "Renames directories with -Dir switch (camelCase)" {
            New-TestDirectory -Path $testPath -Name "my_folder"
            REPWSH-Organization -Camel -Dir -Path $testPath
            
            Test-Path (Join-Path $testPath "myFolder") | Should -Be $true
            Test-Path (Join-Path $testPath "my_folder") | Should -Be $false
        }
        
        It "Renames both files and directories with -Dir switch" {
            New-TestFile -Path $testPath -Name "MyFile.txt"
            New-TestDirectory -Path $testPath -Name "MyFolder"
            REPWSH-Organization -Snake -Dir -Path $testPath
            
            Test-Path (Join-Path $testPath "my_file.txt") | Should -Be $true
            Test-Path (Join-Path $testPath "my_folder") | Should -Be $true
        }
    }
    
    Context "Parameter Validation" {
        
        It "Throws error when no case parameter is specified" {
            { REPWSH-Organization -Path $testPath -ErrorAction Stop } | Should -Throw
        }
        
        It "Throws error when path does not exist" {
            { REPWSH-Organization -Snake -Path "C:\NonExistentPath" -ErrorAction Stop } | Should -Throw
        }
    }
    
    Context "Edge Cases" {
        
        It "Handles files with no extension" {
            New-TestFile -Path $testPath -Name "MyFile"
            REPWSH-Organization -Snake -Path $testPath
            
            Test-Path (Join-Path $testPath "my_file") | Should -Be $true
        }
        
        It "Handles files with multiple dots" {
            New-TestFile -Path $testPath -Name "My.File.Name.txt"
            REPWSH-Organization -Snake -Path $testPath
            
            # Only the last .txt is the extension, middle dots become part of filename
            Test-Path (Join-Path $testPath "my_file_name.txt") | Should -Be $true
        }
        
        It "Skips renaming when target already exists" {
            New-TestFile -Path $testPath -Name "MyFile.txt"
            New-TestFile -Path $testPath -Name "my_file.txt"
            
            REPWSH-Organization -Snake -Path $testPath -WarningVariable warnings
            
            Test-Path (Join-Path $testPath "MyFile.txt") | Should -Be $true
            Test-Path (Join-Path $testPath "my_file.txt") | Should -Be $true
        }
        
        It "Handles numeric characters correctly" {
            New-TestFile -Path $testPath -Name "MyFile123.txt"
            REPWSH-Organization -Snake -Path $testPath
            
            Test-Path (Join-Path $testPath "my_file123.txt") | Should -Be $true
        }
        
        It "Removes multiple consecutive underscores" {
            New-TestFile -Path $testPath -Name "My___File.txt"
            REPWSH-Organization -Snake -Path $testPath
            
            Test-Path (Join-Path $testPath "my_file.txt") | Should -Be $true
        }
    }
    
    Context "Alias" {
        
        It "Can be called using 'rep' alias" {
            New-TestFile -Path $testPath -Name "MyFile.txt"
            rep -Snake -Path $testPath
            
            Test-Path (Join-Path $testPath "my_file.txt") | Should -Be $true
        }
    }
}

# Run the tests with: Invoke-Pester -Path .\RenameFiles.Tests.ps1