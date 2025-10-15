 providers = {
    vsphere = (
      each.value.vsphere_server == "vc-sand-01.roscap.com" ? vsphere.vc-sand-01 :
      each.value.vsphere_server == "bank-vc-01.roscap.com" ? vsphere.bank-vc-01 :
      each.value.vsphere_server == "perun.roscap.com"      ? vsphere.perun :
      each.value.vsphere_server == "vc-b-1001.domrbank.ru" ? vsphere.vc-b-1001 :
      vsphere.vc-sand-01 // fallback, если ни один не совпал
    )
  }
