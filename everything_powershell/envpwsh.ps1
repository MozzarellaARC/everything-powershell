function envs {
    param(
        [string]$Scope,
        [string]$Var,
        # TODO: add value param for SetEnvironmentVariable
        [string]$Value
    )

    # Get the Path environment variable for the current user
    [Environment]::GetEnvironmentVariable($Var, $Scope)
}