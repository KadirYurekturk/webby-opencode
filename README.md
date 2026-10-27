# Webby — OpenCode Spider

Windows masaüstünüzde yaşayan, OpenCode **2.2.0** için küçük bir dijital ASCII örümcek.
Kod yazılırken bacaklarını oynatır, izin gerektiğinde dikkatinizi çeker ve iş bittiğinde kutlar.

![Webby masaüstü maskotu](docs/preview.png)

## Hızlı başlangıç

1. [Releases](https://github.com/kadiryurekturk/webby-opencode/releases) sayfasından ZIP paketini indirin ve bir klasöre çıkartın.
2. **Demo.cmd** dosyasına çift tıklayın. OpenCode olmadan tüm görünümleri deneyebilirsiniz.
3. Gerçek kullanım için OpenCode sunucusuna bağlayın (aşağıda).

**Gereksinimler:** Windows 10/11 masaüstü, yerleşik **Windows PowerShell 5.1** ve WPF/.NET Framework.
Maskot için Node.js, Python, Electron, npm paketi veya derleme aracı kurulmaz. C# ağ yardımcısı ilk açılışta Windows'un yerleşik derleyicisiyle bellekte derlenir.
PowerShell 7 yerine `powershell.exe` kullanın. Kurum politikası PowerShell/Add-Type kullanımını engelliyorsa uygulama çalışmayabilir.

## OpenCode ile kullanma

Önce çalışacağınız proje klasöründe bir terminal açın:

```powershell
opencode serve --hostname 127.0.0.1 --port 4096
```

OpenCode başlangıçta yerel sunucu adresini ve sunucu parolasını gösterir.
İkinci bir **Windows PowerShell** penceresinde, Webby klasöründen:

```powershell
$credential = Get-Credential -UserName opencode -Message 'OpenCode sunucu parolasini girin'
$env:OPENCODE_PASSWORD = $credential.GetNetworkCredential().Password
.\Start-Spider.cmd
```

Bu parola model sağlayıcınızın API anahtarı değildir. Webby parolayı diske yazmaz.
Farklı kullanıcı adı kullanıyorsanız `OPENCODE_SERVER_USERNAME` ortam değişkenini ayarlayın.
Farklı port için ` .\Start-Spider.cmd -ServerUrl http://127.0.0.1:4097` kullanabilirsiniz.

Çalışmak için OpenCode TUI'yi **aynı sunucuya** bağlayın:

```powershell
opencode --server http://127.0.0.1:4096
```

Bu komutu yukarıda `OPENCODE_PASSWORD` ayarladığınız aynı terminalde çalıştırın. Kendi sunucusunu başlatan ayrı bir `opencode` oturumunun olayları bu bağlantıda görünmez.
Parolasız sunucularda doğrudan `Start-Spider.cmd` çalıştırılabilir.

## Kontroller ve durumlar

- **Sürükle:** maskotu taşı.
- **Sağ tık:** animasyonu duraklat, her zaman üstte tut seçeneğini değiştir veya kapat.
- **× / Escape:** kapat. Görev çubuğunda da görünür.
- **READY:** bağlandı, yeni olayları dinliyor.
- **WEAVING CODE:** en az bir oturum çalışıyor.
- **NEEDS YOU:** izin isteği bekliyor; izni OpenCode içinde yanıtlayın.
- **ALL DONE / SNAG IN THE WEB:** tamamlanma veya hata; 8 saniye sonra normal duruma döner.
- **OFFLINE:** sunucu yok veya erişim başarısız; otomatik yeniden bağlanır. Üzerinde bekleyerek bağlantı bilgisini görebilirsiniz.

Birden çok oturum izlenir; bekleyen izinler çalışma durumundan önceliklidir.
Animasyonu duraklatmak durum takibini durdurmaz. Demo her 4 saniyede görünüm değiştirir.

## Kapsam ve gizlilik

Webby bağımsız bir topluluk projesidir; OpenAI veya OpenCode'un resmi maskotu değildir.
Yerel V2 `/api/event` SSE akışını **yalnızca okur**. Komut çalıştırmaz, otomatik izin vermez, konuşma/metin içeriklerini kaydetmez ve telemetri göndermez.
Yalnızca loopback adreslerine bağlanır; kimlik bilgilerini başka bir adrese yönlendirmez.

Maskotu işinizi başlatmadan önce açın. Olay akışı geçmişi tekrar oynatmaz: bağlantıdan önce başlamış işler ve kopukluk sırasında gerçekleşen olaylar yeniden oluşturulmaz. Yeniden bağlanınca READY, yeni olayları dinlediği anlamına gelir; tüm sunucunun boş olduğu anlamına gelmez.
Bu ilk sürüm izin uyarıları gösterir; OpenCode soru formları, oturuma tıklayıp odaklama, sistem tepsisi ve otomatik başlangıç içermez.

## Uyumluluk ve doğrulama

Hedef: **OpenCode v2.2.0**. Gerçek Windows ortamında v2.2.0 ile kimlik doğrulamalı SSE bağlantısı ve WPF pencere açma/kapatma testi yapılmıştır.
Durum geçişleri deterministik testlerle doğrulanır; ücretli model çağrısı gerektiren uçtan uca ajan çalıştırması yapılmamıştır.

Sözleşme kaynakları:
- [V2 HTTP API](https://opencode.ai/v2/docs/api)
- [v2.2.0 oturum olayları](https://github.com/anomalyco/opencode/blob/v2.2.0/packages/schema/src/session-event.ts)
- [v2.2.0 izin olayları](https://github.com/anomalyco/opencode/blob/v2.2.0/packages/schema/src/permission.ts)

```powershell
powershell.exe -NoProfile -File tests/state.tests.ps1
powershell.exe -NoProfile -File tests/stream.tests.ps1
powershell.exe -NoProfile -STA -File Spider.ps1 -Demo -SmokeTest
# Calisan, kimlik bilgileri ortamda ayarlanmis sunucu gerekir:
powershell.exe -NoProfile -File tests/live.tests.ps1 -ServerUrl http://127.0.0.1:4096
```

Dosyalar: `Spider.ps1` arayüzü, `src/State.ps1` durum mantığı, `src/EventStream.cs` arka plan bağlantısı.
MIT lisanslıdır.
