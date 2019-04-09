# Varonis-Remote-Module

## SYNOPSIS

Imports the Varonis Management Module from the Varonis IDU and connects to the IDU
 

## DESCRIPTION
Creates a PowerShell Session with the Varonis IDU and then Imports the Varonis Management Module into the current PowerShell session for the cmdlets to be used while being connected to the IDU. This essentially acts as a wrapper to the Varonis Powershell Module that was developed by Varonis so it can be used without getting onto the IDU/probe servers.
 
## EXAMPLE
`Connect-Varonis -ServerName VaronisIDU`

Connects to the Varonis idu server
