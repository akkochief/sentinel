# BPS SH

BPS SH; Linux, Windows Git Bash ve WSL üzerinde çalışan, ana kodu tamamen
`bps.sh` olan eşzamanlı TCP Connect port tarayıcıdır.

> Yalnızca sahibi olduğunuz veya açık izin aldığınız sistemleri tarayın.

## Dosyalar

- `bps.sh`: Ana ve çalıştırılabilir tarayıcı kodu
- `run-windows.bat`: Windows'ta Git Bash üzerinden başlatıcı
- `targets.example.txt`: Hedef dosyası örneği
- `tests/test_bps.sh`: Shell birim ve yerel entegrasyon testleri

## Gereksinimler

Zorunlu:

- Bash 4.3+
- `timeout`, `awk`, `sort`, `sed`, `tr`, `cut`, `mktemp`, `date`

İsteğe bağlı:

- `curl`: `--http-info` için
- `openssl`: `--tls-info` için
- `getent` veya `nslookup`: `--reverse-dns` için

Linux dağıtımlarında temel araçlar genellikle kurulu gelir. Windows'ta en kolay
yol güncel Git for Windows/Git Bash kullanmaktır.

## Linux

```bash
chmod +x bps.sh
./bps.sh 127.0.0.1
```

Sistem genelinde komut olarak kullanmak isterseniz:

```bash
sudo install -m 0755 bps.sh /usr/local/bin/bps
bps 127.0.0.1
```

## Windows

Önce Git for Windows kurun. Ardından ZIP içindeki klasörde:

```bat
run-windows.bat 127.0.0.1 -p 1-1000
```

Git Bash terminalinden doğrudan:

```bash
./bps.sh 127.0.0.1 -p 1-1000
```

`.sh` dosyası CMD veya PowerShell tarafından doğrudan çalıştırılamaz.
`run-windows.bat`, Git Bash'i bulup `bps.sh` dosyasını çalıştırır.

WSL kullanıyorsanız ZIP'i WSL erişimli bir klasöre çıkarıp:

```bash
bash bps.sh 127.0.0.1
```

## Hedef biçimleri

```bash
./bps.sh 192.168.1.10
./bps.sh 192.168.1.10,192.168.1.20
./bps.sh 192.168.1.10-192.168.1.30
./bps.sh 192.168.1.0/24
./bps.sh server.example.local
./bps.sh --targets-file targets.example.txt
```

Shell sürümünde tek IPv6 adresi denenebilir; IPv6 CIDR genişletme desteklenmez.

## Port seçimi

```bash
./bps.sh 192.168.1.10 -p 22,80,443,8000-8100
./bps.sh 192.168.1.10 -p full
./bps.sh 192.168.1.10 -p 1-10000 --exclude-ports 135,139,445
```

Preset'ler:

| Preset | İçerik |
|---|---|
| `common` | Yaygın TCP portları |
| `web` | HTTP/HTTPS ve web geliştirme portları |
| `database` | SQL, NoSQL, cache ve mesaj kuyruğu |
| `remote` | SSH, Telnet, RDP, VNC ve WinRM |
| `mail` | SMTP, POP3 ve IMAP |
| `fileshare` | FTP, SMB, NFS ve Rsync |
| `devops` | Docker, Kubernetes, Git ve gözlemleme |
| `full` | `1-65535` |

## Hız, eşzamanlılık ve retry

```bash
./bps.sh 192.168.1.10 -p full \
  --concurrency 200 \
  --rate 500 \
  --timeout 0.6 \
  --retries 1 \
  --progress 2
```

- `--concurrency`: Aynı anda çalışan tarama işi.
- `--rate`: Saniyede başlatılan azami iş; `0` sınırsızdır.
- `--timeout`: TCP bağlantı zaman aşımı.
- `--retries`: Timeout sonuçlarını en fazla üç kez yeniden dener.
- `--progress`: Belirtilen saniye aralığında ilerleme verir.

## Banner, HTTP ve TLS

```bash
./bps.sh server.local -p common --banner
./bps.sh web.local -p web --http-info --tls-info
./bps.sh 192.168.1.10 -p 1-10000 --http-info --probe-all-http
```

- `--banner`, açık bağlantıda veri göndermeden bir satır bekler.
- `--http-info`, açık web portuna HTTP `HEAD /` gönderir ve durum, `Server`,
  `Location` alanlarını alır.
- `--tls-info`, bilinen TLS portlarında TLS sürümü, cipher ve sertifikanın
  SHA-256 parmak izini alır.
- `--probe-all-http`, HTTP kontrolünü tüm açık portlarda dener.

## JSON, CSV ve TXT

```bash
./bps.sh 192.168.1.10 -p common \
  --banner \
  --http-info \
  --tls-info \
  --json result.json \
  --csv result.csv \
  --txt result.txt
```

Varsayılan olarak raporlarda yalnızca açık portlar bulunur.
`--include-closed`, kapalı ve filtreli sonuçları da konsola ve dosyalara ekler.

## CI kullanımı

```bash
./bps.sh 127.0.0.1 -p 22,3306,6379 --fail-on-open --quiet
```

Çıkış kodları:

| Kod | Anlam |
|---:|---|
| `0` | Tarama tamamlandı |
| `2` | Komut/giriş/bağımlılık hatası |
| `10` | `--fail-on-open` ile açık port bulundu |
| `130` | Ctrl+C ile durduruldu |

## Test

```bash
bash -n bps.sh
bash tests/test_bps.sh
```

Entegrasyon testi yalnızca `127.0.0.1` üzerinde geçici HTTP sunucusu kullanır.

## Sınırlamalar

- TCP Connect taraması yapar; SYN/raw-socket ve gizleme özellikleri yoktur.
- UDP taraması yoktur.
- Shell ve `/dev/tcp` yapısı nedeniyle Python sürümünden daha yavaş olabilir.
- Windows'ta CMD yerine Git Bash veya WSL gerekir.
- Servis adı port numarasından tahmindir; kesin ürün/sürüm tespiti değildir.
