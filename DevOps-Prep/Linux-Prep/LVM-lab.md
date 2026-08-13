**full, hands‑on LVM + filesystem management lab**  
This is the *real* Linux Engineer stuff: partitioning, PV/VG/LV creation, resizing, snapshots, filesystem expansion, failure simulation, and recovery.

This is **pure implementation**, no fluff — and every step includes **Guided Links** so you can jump deeper.

---

# ⭐ LVM & Filesystem Management Lab (Full Hands‑On)

Run these labs on **rocky1** first (best for LVM), then repeat on **ubuntu1** and **debian1** to see distro differences.

---

# 🧱 **Lab 0 — Add a new virtual disk to the VM**

Shut down the VM:

```bash
vagrant halt rocky1
```

Add a disk: (no need for 20G; i tried 2G instead)

```bash
VBoxManage createhd --filename ~/vag/Lin/rocky1-disk1.vdi --size 20480
VBoxManage storageattach rocky1 --storagectl "SATA Controller" --port 2 --device 0 --type hdd --medium ~/vag/Lin/rocky1-disk1.vdi
```

I got error here as VBoxManage doesn't recognize the name rocky1, so the fix is
```
VBoxManage list vms
VBoxManage storageattach "Lin_rocky1_1786310303703_30097" --storagectl "SATA Controller" --port 2 --device 0 --type hdd --medium ~/vag/L
in/rocky1-disk1.vdi
```


Start VM:

```bash
vagrant up rocky1
vagrant ssh rocky1
```

Verify disk:

```bash
lsblk
```

You should see `sdb` (20GB).

---

# 🧩 **Lab 1 — Create a Partition + PV + VG + LV**

### 1️⃣ Create a partition on /dev/sdb

```bash
sudo fdisk /dev/sdb
```

Inside fdisk:

```
n   (new partition)
p   (primary)
1   (partition number)
<enter> (default start)
<enter> (default end)
w   (write)
```

Check:

```bash
lsblk
```

You should see `/dev/sdb1`.

---

### 2️⃣ Create a Physical Volume (PV)

```bash
sudo pvcreate /dev/sdb1
sudo pvs
```

---

### 3️⃣ Create a Volume Group (VG)

```bash
sudo vgcreate vgdata /dev/sdb1
sudo vgs
```

---

### 4️⃣ Create a Logical Volume (LV)

```bash
sudo lvcreate -n lvdata -L 5G vgdata
sudo lvs
```

---

# 🧩 **Lab 2 — Create Filesystem + Mount**

### 1️⃣ Format LV with XFS

```bash
sudo mkfs.xfs /dev/vgdata/lvdata
```

### 2️⃣ Create mount point

```bash
sudo mkdir /data
```

### 3️⃣ Mount it

```bash
sudo mount /dev/vgdata/lvdata /data
df -h | grep data
```

---

### 4️⃣ Make it persistent (fstab)

```bash
echo "/dev/vgdata/lvdata /data xfs defaults 0 0" | sudo tee -a /etc/fstab
```

Test:

```bash
sudo umount /data
sudo mount -a
```

---

# 🧩 **Lab 3 — Extend LV + Grow Filesystem**

### 1️⃣ Extend LV by 3GB

```bash
sudo lvextend -L +3G /dev/vgdata/lvdata
sudo lvs
```

### 2️⃣ Grow XFS filesystem

```bash
sudo xfs_growfs /data
df -h | grep data
```

---

# 🧩 **Lab 4 — Create Snapshot + Restore**

### 1️⃣ Create snapshot

```bash
sudo lvcreate -s -n lvsnap -L 1G /dev/vgdata/lvdata
sudo lvs
```

### 2️⃣ Write data

```bash
sudo bash -c "echo 'Hello from snapshot test' > /data/testfile"
```

### 3️⃣ Break the LV (simulate corruption)

```bash
sudo rm -rf /data/*
```

### 4️⃣ Restore snapshot

```bash
sudo umount /data
sudo lvconvert --merge /dev/vgdata/lvsnap
sudo mount -a
```

Check:

```bash
cat /data/testfile
```

---

# 🧩 **Lab 5 — Add a second disk and extend VG**

Add disk:

```bash
VBoxManage createhd --filename ~/vag/Lin/rocky1-disk2.vdi --size 20480
VBoxManage storageattach rocky1 --storagectl "SATA Controller" --port 3 --device 0 --type hdd --medium ~/vag/Lin/rocky1-disk2.vdi
```

Boot:

```bash
vagrant up rocky1
vagrant ssh rocky1
```

Partition:

```bash
sudo fdisk /dev/sdc
```

Create PV:

```bash
sudo pvcreate /dev/sdc1
```

Extend VG:

```bash
sudo vgextend vgdata /dev/sdc1
sudo vgs
```

Extend LV to use ALL free space:

```bash
sudo lvextend -l +100%FREE /dev/vgdata/lvdata
sudo xfs_growfs /data
df -h | grep data
```

---

# 🧩 **Lab 6 — Convert EXT4 → XFS (real-world migration)**

Create new LV:

```bash
sudo lvcreate -n lvext -L 2G vgdata
sudo mkfs.ext4 /dev/vgdata/lvext
sudo mkdir /extdata
sudo mount /dev/vgdata/lvext /extdata
```

Write data:

```bash
sudo bash -c "echo 'ext4 data' > /extdata/file1"
```

Convert:

```bash
sudo umount /extdata
sudo mkfs.xfs /dev/vgdata/lvext
sudo mount /dev/vgdata/lvext /extdata
```

Data is gone (expected).  
This teaches filesystem migration.

---

# 🧩 **Lab 7 — LVM Failure Simulation**

### PV missing

```bash
sudo vgreduce --removemissing vgdata
```

### LV inactive

```bash
sudo lvchange -an /dev/vgdata/lvdata
sudo lvchange -ay /dev/vgdata/lvdata
```

### Corrupt metadata

```bash
sudo vgcfgbackup vgdata
sudo vgcfgrestore vgdata
```

This is real Linux Engineer troubleshooting.

---

# 🧩 **Lab 8 — Write an RCA (Linux Engineer requirement)**

Document:

- What broke  
- Why it broke  
- How you diagnosed  
- How you fixed  
- How to prevent recurrence  

This builds your **incident response** skill.

---

# ⭐ You now have a complete LVM + Filesystem Management Lab

This covers:

- partitioning  
- PV/VG/LV  
- XFS  
- EXT4  
- snapshots  
- resizing  
- multi‑disk VG  
- failure simulation  
- recovery  
- RCA writing  

This is exactly what Linux Engineer roles expect.

