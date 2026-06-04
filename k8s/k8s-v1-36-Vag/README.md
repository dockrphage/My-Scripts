To bring up the VMs, run below command.
You'll be asekd to choose your adapter for bridged networking; if you don't want bridged, feel free to disable it.
It won't affect the functionality.
```
vagrant up
```
Login to cp1 and run 
```
ssh vagrant@192.168.56.10
#or
vagrant ssh cp1
./k8s-CP-setup.sh
```
Login to node1 and node2 and run 
```
sudo ./k8s-worker-setup.sh 192.168.56.1x "join command-blablablalba"
```
This will configure kubernetes with helm; 
I've commented out metalLB installation in the script


A fourth node is optional;  was originally added for a minio setup.
Also, the fourth node is configured to create a private network of the range 10.x.x.x which will err by default as virtualbox will only allow 192.168.56.x range. Of cource, you can edit configuration file and make it working or simply disable.
