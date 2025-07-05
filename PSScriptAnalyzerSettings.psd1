@{
    # Enable all severity levels
    Severity = @('Error', 'Warning', 'Information')
    
    # Explicitly include the unused variable rule
    IncludeRules = @(
        'PSUseDeclaredVarsMoreThanAssignments',  # Unused variables
        'PSAvoidUsingCmdletAliases',
        'PSUseApprovedVerbs',
        'PSReservedCmdletChar',
        'PSReservedParams',
        'PSMisleadingBacktick'
    )
    
    # Make sure to include default rules
    IncludeDefaultRules = $true
}
