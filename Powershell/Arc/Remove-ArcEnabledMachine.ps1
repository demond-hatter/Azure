$subid = '1d58a9fe-3cc7-47b1-b68c-d34e2b24290b'
$resGroup = 'ArcDemo'
$mName = ''

connect-azaccount
set-azcontext
import-module az.connectedmachine

get-AzConnectedMachineExtension -SubscriptionId $subid -ResourceGroupName $resGroup -MachineName | Remove-AzConnectedMachineExtension 
Remove-AzConnectedMachine -SubscriptionId $subid -ResourceGroupName $resGroup -Name $mName