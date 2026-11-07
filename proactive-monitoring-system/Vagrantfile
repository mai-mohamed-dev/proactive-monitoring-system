Vagrant.configure("2") do |config|
  config.hostmanager.enabled = true
  config.hostmanager.manage_host = true
  # Disable automatic box update checking
  config.vm.box_check_update = false
  config.vm.define "monitor" do |m|
    m.vm.box = "ubuntu/jammy64"
    m.vm.hostname = "monitor-server"
    m.vm.network "private_network", ip: "192.168.56.10"
    m.vm.provision "shell", path: "monitor_provision.sh"
    m.vm.synced_folder "./auto", "/vagrant"
    m.vm.provider "virtualbox" do |v|
      v.name = "monitor-server"
      v.memory = 2048
      v.cpus = 2
    end
  end
end