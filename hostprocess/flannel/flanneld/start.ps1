$ErrorActionPreference = "Stop";

# flannel uses host-local, flannel.exe, and sdnoverlay so copy that to the correct location
Write-Output "Copying SDN CNI binaries to host"
mkdir -force $env:CNI_BIN_PATH
Copy-Item -Path "$env:CONTAINER_SANDBOX_MOUNT_POINT/cni/*" -Destination "$env:CNI_BIN_PATH" -Force

Write-Host "copy flannel config"
mkdir -force C:\etc\kube-flannel\
ls C:\etc\kube-flannel\
ls $env:CONTAINER_SANDBOX_MOUNT_POINT/mounts/kube-flannel-windows/
cp -force $env:CONTAINER_SANDBOX_MOUNT_POINT/mounts/kube-flannel-windows/net-conf.json  C:\etc\kube-flannel\net-conf.json

# configure cni
# get info
Write-Host "update cni config"
$cniJson = get-content $env:CONTAINER_SANDBOX_MOUNT_POINT/mounts/kube-flannel-windows/cni-conf-containerd.json | ConvertFrom-Json
$serviceSubnet = $env:SERVICE_SUBNET
$podSubnet = (get-content $env:CONTAINER_SANDBOX_MOUNT_POINT/mounts/kube-flannel-windows/net-conf.json | ConvertFrom-Json).Network
$na = Get-NetRoute | Where { $_.DestinationPrefix -eq '0.0.0.0/0' } | Select-Object -Property ifIndex
$managementIP = (Get-NetIPAddress -ifIndex $na[0].ifIndex -AddressFamily IPv4).IPAddress

#set info and save
$cniJson.delegate.AdditionalArgs[0].Value.Settings.Exceptions = $serviceSubnet, $podSubnet
$cniJson.delegate.AdditionalArgs[1].Value.Settings.DestinationPrefix = $serviceSubnet
$cniJson.delegate.AdditionalArgs[2].Value.Settings.ProviderAddress = $managementIP
mkdir -force $env:CNI_CONFIG_PATH
Set-Content -Path $env:CNI_CONFIG_PATH/10-flannel.conf ($cniJson | ConvertTo-Json -depth 100)

# set route for metadata servers in clouds
# https://github.com/kubernetes-sigs/sig-windows-tools/issues/36
Write-Host "add route"
route /p add 169.254.169.254 mask 255.255.255.255 0.0.0.0

Write-Host "envs"
write-host $env:POD_NAME
write-host $env:POD_NAMESPACE

Write-Host "Starting flannel"
& $env:CONTAINER_SANDBOX_MOUNT_POINT/flannel/flanneld.exe --kube-subnet-mgr --iface $managementIP
