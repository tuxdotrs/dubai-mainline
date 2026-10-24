# Without the ADSP firmware running, pmic-glink can't report the Type-C role
# and the USB controller never becomes a peripheral, so no gadget shows up.
# Force device mode before the gadget is bound; it stays set in stage-2.
class Tasks::USBRoleDevice < SingletonTask
  def initialize()
    add_dependency(:Mount, "/sys")
    add_dependency(:Files, "/sys/class/usb_role/*/role")
    Tasks::SetupGadgetMode.instance.add_dependency(:Task, self)
  end

  def run()
    Dir.glob("/sys/class/usb_role/*/role").each do |role|
      log("Setting #{role} to device")
      System.write(role, "device")
    end
  end
end
