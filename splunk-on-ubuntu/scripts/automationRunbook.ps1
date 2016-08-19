$VerbosePreference = "SilentlyContinue"

$conn = Get-AutomationConnection -Name AzureRunAsConnection
Add-AzureRmAccount `
    -ServicePrincipal `
    -Tenant $conn.TenantID -ApplicationId $conn.ApplicationId `
    -CertificateThumbprint $conn.CertificateThumbprint

$rgName = Get-AutomationVariable -Name 'splunk_resourceGroup'
$templateUri = Get-AutomationVariable -Name 'splunk_templateUri'

$removeVM = $true

if ($removeVM) {
	# delete the failed cluster master	
	Remove-AzureRmVM -ResourceGroupName $rgName -Name cm-vm -Force

	# remove his vhds
	$accts = Get-AzureRmStorageAccount -ResourceGroupName $rgName
	$acct0 = $accts[0].StorageAccountName

	$acctKeys = Get-AzureRmStorageAccountKey -ResourceGroupName $rgName -Name $acct0
	$acctKey = $acctKeys[0].Value

	$ctx = New-AzureStorageContext -StorageAccountName $acct0 -StorageAccountKey $acctKey

	Remove-AzureStorageBlob -Context $ctx -Container vhds -Blob 'cm-vm-osdisk.vhd'  -ErrorAction SilentlyContinue
	Remove-AzureStorageBlob -Context $ctx -Container vhds -Blob 'cm-vm-datadisk1.vhd'  -ErrorAction SilentlyContinue
	Remove-AzureStorageBlob -Context $ctx -Container vhds -Blob 'cm-vm-datadisk2.vhd'  -ErrorAction SilentlyContinue
   
}

$machineSettingsString = Get-AutomationVariable -Name 'splunk_machineSettings'
$osSettingsString = Get-AutomationVariable -Name 'splunk_osSettings'
$storageSettingsString = Get-AutomationVariable -Name 'splunk_storageSettings'
$adminUsernameString = Get-AutomationVariable -Name 'splunk_adminUsername'
$adminPasswordString = Get-AutomationVariable -Name 'splunk_adminPassword'
$splunkAdminPasswordString = Get-AutomationVariable -Name 'splunk_splunkAdminPassword'
$locationString = Get-AutomationVariable -Name 'splunk_location'
$namespaceString = Get-AutomationVariable -Name 'splunk_namespace'
$securityGroupNameString = Get-AutomationVariable -Name 'splunk_securityGroupName'
$splunkServerRoleString = Get-AutomationVariable -Name 'splunk_splunkServerRole'
$subnetString = Get-AutomationVariable -Name 'splunk_subnet'

# machineSettings
$machineSettingsObject = ConvertFrom-Json -InputObject $machineSettingsString
$machineSettings = @{ `
	'vmSize' = $machineSettingsObject.vmSize; `
	'diskSize' = $machineSettingsObject.diskSize; `
	'staticIp' = $machineSettingsObject.staticIp; `
	'clusterMasterIp' = $machineSettingsObject.clusterMasterIp; `
	'publicIPName' = $machineSettingsObject.publicIPName; `
	'availabilitySet' = $machineSettingsObject.availabilitySet `
}

# osSettings
$osSettingsObject = ConvertFrom-Json -InputObject $osSettingsString
$imageReference = @{ `
	'publisher' = $osSettingsObject.imageReference.publisher; `
	'offer' = $osSettingsObject.imageReference.offer; `
	'sku' = $osSettingsObject.imageReference.sku; `
	'version' = $osSettingsObject.imageReference.version `
}
$scripts = @($osSettingsObject.scripts[0], $osSettingsObject.scripts[1])	
$osSettings = @{"imageReference"=$imageReference; "scripts"=$scripts}

# storageSettings
$storageSettingsObject = ConvertFrom-Json -InputObject $storageSettingsString
$storageSettings = @{
	'name' = $storageSettingsObject.name; `
	'type' = $storageSettingsObject.type; `
	'count' = $storageSettingsObject.count; `
	'map' = $storageSettingsObject.map `
}

# the rest

$parameters = @{}
$parameters.Add("location", $locationString)
$parameters.Add("adminUsername", $adminUsernameString)
$parameters.Add("adminPassword", $adminPasswordString)
$parameters.Add("namespace", $namespaceString)
$parameters.Add("securityGroupName", $securityGroupNameString)
$parameters.Add("splunkAdminPassword", $splunkAdminPasswordString)
$parameters.Add("splunkServerRole", $splunkServerRoleString)
$parameters.Add("subnet", $subnetString)
$parameters.Add("osSettings", $osSettings)
$parameters.Add("machineSettings", $machineSettings)
$parameters.Add("storageSettings", $storageSettings)

# run the template that adds a new cluster master
New-AzureRmResourceGroupDeployment `
	-Mode Incremental `
	-Name goliveTestingDeployment `
	-ResourceGroupName $rgName `
	-TemplateUri $templateUri `
	-TemplateParameterObject $parameters
