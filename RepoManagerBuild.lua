require "import"
import "android.widget.*"
import "android.view.View"
import "android.os.*"
import "android.util.Base64"
import "android.content.*"
import "android.net.Uri"
import "java.net.URL"
import "java.lang.*"
import "java.io.*"
import "java.util.zip.ZipInputStream"
import "java.lang.reflect.Array"
import "org.json.*"
local C=...
local token=C.getToken()
local gasUrl="https://script.google.com/macros/s/AKfycbzujW6uKWRMPtGUmOFBmHB52GKQDC3PuEk0z-ZzxuO7Ib1Zn697uz-Fa-Ed33-znsg/exec"
local baseDir,bg,closeAllAndResume,confirmDialog,contentsUrl,dlg=C.baseDir,C.bg,C.closeAllAndResume,C.confirmDialog,C.contentsUrl,C.dlg
local encodeURI,errInfo,esc,ghRequest,inp,jarr=C.encodeURI,C.errInfo,C.esc,C.ghRequest,C.inp,C.jarr
local jobj,mainH,mkbtn,num,readAll,readFileBytes=C.jobj,C.mainH,C.mkbtn,C.num,C.readAll,C.readFileBytes
local say,setBackAction,showFilePicker,trim,txt,ui=C.say,C.setBackAction,C.showFilePicker,C.trim,C.txt,C.ui
local vbox=C.vbox
local fetchReleases, showReleasesList, showCreateRelease, deleteReleaseApi, showEditRelease, showManageAssets, uploadAssetApi, fetchWorkflows, showWorkflowsList, dispatchWorkflowApi, setupGithubActions, uploadSecretApi, checkExistingSecrets, showSecretManager, fetchWorkflowRuns, showWorkflowRuns, fetchRunArtifacts, downloadArtifact
setupGithubActions=function(repoFullName,onReady)
local yamlContent=[[
name: Bangun APK Otomatis
on:
  workflow_dispatch:
    inputs:
      r8:
        description: Aktifkan R8 (perkecil dan kaburkan kode, hasilnya build release)
        type: boolean
        default: false
      sign:
        description: Tanda tangani dengan kunci pribadi jika tersedia
        type: boolean
        default: true
jobs:
  build:
    runs-on: ubuntu-latest
    timeout-minutes: 45
    steps:
      - name: Checkout Repo
        uses: actions/checkout@v6
      - name: Setup JDK 17
        uses: actions/setup-java@v5
        with:
          java-version: '17'
          distribution: 'temurin'
      - name: Siapkan Android SDK
        run: |
          SDK="${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
          echo "SDK: $SDK"
          yes | "$SDK/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$SDK" --licenses > /dev/null || true
      - name: Ekstrak File ZIP
        run: |
          find . -name "*.zip" -type f -not -path "./.git/*" | while IFS= read -r f; do
            echo "Mengekstrak: $f"
            unzip -q -o "$f" -d "$(dirname "$f")" || echo "Peringatan unzip: $f"
          done
      - name: Bersihkan Konfigurasi Lokal
        run: |
          find . -name "local.properties" -type f -delete
          find . -name "gradle.properties" -type f -exec sed -i -e '/aapt2FromMavenOverride/d' -e '/org.gradle.java.home/d' -e 's/\r$//' {} +
      - name: Cache Gradle
        uses: actions/cache@v5
        with:
          path: |
            ~/.gradle/caches
            ~/.gradle/wrapper
          key: gradle-${{ runner.os }}-${{ hashFiles('**/*.gradle*', '**/gradle-wrapper.properties') }}
          restore-keys: |
            gradle-${{ runner.os }}-
      - name: Cari dan Eksekusi Gradle
        env:
          R8: ${{ inputs.r8 }}
        run: |
          TASK=assembleDebug
          GARGS="--no-daemon"
          if [ "$R8" = "true" ]; then
            TASK=assembleRelease
            cat > "$RUNNER_TEMP/r8.init.gradle" <<'GRADLE'
          allprojects {
            afterEvaluate { proj ->
              if (proj.plugins.hasPlugin("com.android.application")) {
                def rel = proj.android.buildTypes.getByName("release")
                rel.minifyEnabled = true
                rel.shrinkResources = true
                rel.proguardFiles(proj.android.getDefaultProguardFile("proguard-android-optimize.txt"))
                try { proj.android.lint.checkReleaseBuilds = false } catch (ignored) { }
              }
            }
          }
          GRADLE
            GARGS="$GARGS -I $RUNNER_TEMP/r8.init.gradle"
            echo "R8 aktif: membangun varian release dengan minify dan shrinkResources."
          fi
          GRADLE_FILE=$(find . -name "gradlew" -type f | awk '{print length($0) " " $0}' | sort -n | head -n 1 | cut -d' ' -f2-)
          if [ -n "$GRADLE_FILE" ]; then
            echo "gradlew DITEMUKAN di dalam ZIP/proyek: $GRADLE_FILE"
            cd "$(dirname "$GRADLE_FILE")"
            sed -i 's/\r$//' gradlew
            chmod +x gradlew
            ./gradlew $TASK $GARGS
          else
            SETTINGS=$(find . \( -name "settings.gradle" -o -name "settings.gradle.kts" \) -type f | awk '{print length($0) " " $0}' | sort -n | head -n 1 | cut -d' ' -f2-)
            if [ -n "$SETTINGS" ]; then
              echo "gradlew TIDAK ADA di dalam ZIP/proyek. Wrapper akan dibuat otomatis saat build."
              cd "$(dirname "$SETTINGS")"
              GV=""
              WP=$(find . -name "gradle-wrapper.properties" -type f | head -n 1)
              if [ -n "$WP" ]; then
                GV=$(sed -n 's/.*gradle-\([0-9][0-9.]*\)-\(bin\|all\)\.zip.*/\1/p' "$WP" | head -n 1 || true)
              fi
              if [ -z "$GV" ]; then
                AGP=$(grep -rhoE "com\.android\.tools\.build:gradle:[0-9]+\.[0-9]+" --include="*.gradle" --include="*.kts" . | head -n 1 | grep -oE "[0-9]+\.[0-9]+$" || true)
                if [ -z "$AGP" ]; then AGP=$(grep -rhoE "com\.android\.(application|library)[^0-9]{1,30}[0-9]+\.[0-9]+" --include="*.gradle" --include="*.kts" . | head -n 1 | grep -oE "[0-9]+\.[0-9]+$" || true); fi
                if [ -z "$AGP" ]; then AGP=$(grep -rhE "^agp *=" --include="*.toml" . | head -n 1 | grep -oE "[0-9]+\.[0-9]+" | head -n 1 || true); fi
                echo "Versi AGP terdeteksi: ${AGP:-tidak diketahui}"
                case "$AGP" in
                  7.0|7.1) GV=7.4.2 ;;
                  7.2|7.3) GV=7.5.1 ;;
                  7.4) GV=7.6.4 ;;
                  8.0|8.1) GV=8.0.2 ;;
                  8.2) GV=8.2.1 ;;
                  8.3) GV=8.4 ;;
                  8.4) GV=8.6 ;;
                  8.5|8.6) GV=8.7 ;;
                  8.7) GV=8.9 ;;
                  8.8) GV=8.10.2 ;;
                  8.9|8.10) GV=8.11.1 ;;
                  8.11|8.12|8.13) GV=8.14.3 ;;
                  *) GV=8.9 ;;
                esac
              fi
              echo "Memakai Gradle $GV"
              curl -fsSL -o "$RUNNER_TEMP/gradle-dist.zip" "https://services.gradle.org/distributions/gradle-$GV-bin.zip"
              unzip -q -o "$RUNNER_TEMP/gradle-dist.zip" -d "$RUNNER_TEMP"
              GBIN="$RUNNER_TEMP/gradle-$GV/bin/gradle"
              if "$GBIN" wrapper --gradle-version "$GV" --no-daemon; then
                echo "gradlew berhasil dibuat otomatis (Gradle $GV)."
                chmod +x gradlew
                ./gradlew $TASK $GARGS
              else
                echo "Gagal membuat wrapper, memakai Gradle $GV secara langsung."
                "$GBIN" $TASK $GARGS
              fi
            else
              echo "Tidak ada proyek Gradle di repositori ini. Isi repositori:"
              find . -maxdepth 3 -not -path "./.git/*" | head -n 100
              exit 1
            fi
          fi
      - name: Tanda Tangani APK (Opsional)
        env:
          KEYSTORE_B64: ${{ secrets.KEYSTORE_BASE64 }}
          SIGN_KEY_B64: ${{ secrets.SIGN_KEY_BASE64 }}
          SIGN_CERT_B64: ${{ secrets.SIGN_CERT_BASE64 }}
          KEY_ALIAS: ${{ secrets.KEY_ALIAS }}
          KEYSTORE_PASS: ${{ secrets.KEYSTORE_PASSWORD }}
          KEY_PASS: ${{ secrets.KEY_PASSWORD }}
          R8: ${{ inputs.r8 }}
          SIGN: ${{ inputs.sign }}
        run: |
          W="$RUNNER_TEMP/sign"
          mkdir -p "$W"
          KS=""
          STYPE=""
          ALIAS="$KEY_ALIAS"
          export SPASS="$KEYSTORE_PASS"
          export KPASS="${KEY_PASS:-$KEYSTORE_PASS}"
          if [ "$SIGN" = "false" ]; then KEYSTORE_B64=""; SIGN_KEY_B64=""; SIGN_CERT_B64=""; echo "Kunci pribadi dilewati sesuai pilihan."; fi
          if [ -n "$SIGN_KEY_B64" ] && [ -n "$SIGN_CERT_B64" ]; then
            echo "Jenis tanda tangan: kunci + sertifikat"
            echo "$SIGN_KEY_B64" | base64 -d > "$W/key.in"
            echo "$SIGN_CERT_B64" | base64 -d > "$W/cert.in"
            if grep -q "BEGIN" "$W/key.in"; then cp "$W/key.in" "$W/key.pem"; else openssl pkcs8 -inform DER -nocrypt -in "$W/key.in" -out "$W/key.pem"; fi
            if grep -q "BEGIN" "$W/cert.in"; then cp "$W/cert.in" "$W/cert.pem"; else openssl x509 -inform DER -in "$W/cert.in" -out "$W/cert.pem"; fi
            export SPASS=$(openssl rand -hex 12)
            export KPASS="$SPASS"
            ALIAS="sign"
            PIN=""
            if [ -n "$KEY_PASS" ]; then PIN="-passin env:KEY_PASS"; fi
            openssl pkcs12 -export -inkey "$W/key.pem" -in "$W/cert.pem" -name "$ALIAS" -out "$W/ks.p12" -passout "pass:$SPASS" $PIN
            KS="$W/ks.p12"
            STYPE="pkcs12"
          elif [ -n "$KEYSTORE_B64" ]; then
            echo "Jenis tanda tangan: keystore"
            echo "$KEYSTORE_B64" | base64 -d > "$W/ks.in"
            MAGIC=$(head -c 4 "$W/ks.in" | od -An -tx1 | tr -d ' \n')
            case "$MAGIC" in
              feedfeed) STYPE="jks" ;;
              cececece) STYPE="jceks" ;;
              30*) STYPE="pkcs12" ;;
              *) STYPE="bks" ;;
            esac
            echo "Format keystore terdeteksi: $STYPE"
            if [ "$STYPE" = "bks" ]; then
              curl -fsSL -o "$W/bc.jar" https://repo1.maven.org/maven2/org/bouncycastle/bcprov-jdk18on/1.78.1/bcprov-jdk18on-1.78.1.jar
              keytool -importkeystore -srckeystore "$W/ks.in" -srcstoretype BKS -srcstorepass "$SPASS" -destkeystore "$W/ks.p12" -deststoretype PKCS12 -deststorepass "$SPASS" -noprompt -providerclass org.bouncycastle.jce.provider.BouncyCastleProvider -providerpath "$W/bc.jar"
              mv "$W/ks.p12" "$W/ks.in"
              STYPE="pkcs12"
            fi
            if [ "$STYPE" = "pkcs12" ]; then export KPASS="$SPASS"; fi
            keytool -list -keystore "$W/ks.in" -storetype "$STYPE" -storepass "$SPASS" > /dev/null || { echo "Keystore tidak dapat dibaca. Periksa jenis file dan sandinya."; exit 1; }
            KS="$W/ks.in"
          fi
          if [ -z "$KS" ] && [ "$R8" = "true" ]; then
            echo "Build release tanpa kunci pribadi: memakai kunci debug sementara."
            export SPASS=android
            export KPASS=android
            ALIAS=androiddebugkey
            keytool -genkeypair -keystore "$W/debug.p12" -storetype PKCS12 -alias "$ALIAS" -keyalg RSA -keysize 2048 -validity 10000 -storepass android -keypass android -dname "CN=Android Debug,O=Android,C=US"
            KS="$W/debug.p12"
            STYPE="pkcs12"
          fi
          if [ -n "$KS" ]; then
            SDK="${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
            BT=$(ls -d "$SDK"/build-tools/* | sort -V | tail -n 1)
            echo "Build-tools: $BT"
            while IFS= read -r apk; do
              echo "Menandatangani: $apk"
              "$BT/zipalign" -f -p 4 "$apk" "$apk.aligned"
              mv -f "$apk.aligned" "$apk"
              if [ -n "$ALIAS" ]; then
                "$BT/apksigner" sign --ks "$KS" --ks-type "$STYPE" --ks-key-alias "$ALIAS" --ks-pass env:SPASS --key-pass env:KPASS "$apk"
              else
                "$BT/apksigner" sign --ks "$KS" --ks-type "$STYPE" --ks-pass env:SPASS --key-pass env:KPASS "$apk"
              fi
              "$BT/apksigner" verify "$apk"
            done < <(find . -path "*/build/outputs/apk/*" -name "*.apk")
            rm -rf "$W"
          else
            echo "Tanda tangan pribadi tidak ditemukan. Menggunakan debug standar."
          fi
      - name: Beri Nama APK
        id: nama
        run: |
          SDK="${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
          BT=$(ls -d "$SDK"/build-tools/* | sort -V | tail -n 1)
          echo "artifact=Hasil-APK" >> "$GITHUB_OUTPUT"
          IDX=0
          while IFS= read -r apk; do
            BADGING=$("$BT/aapt2" dump badging "$apk" 2>/dev/null || true)
            LABEL=$(echo "$BADGING" | sed -n "s/^application-label:'\(.*\)'.*/\1/p" | head -n 1)
            PKG=$(echo "$BADGING" | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -n 1)
            VNAME=$(echo "$BADGING" | grep "^package:" | sed -n "s/.* versionName='\([^']*\)'.*/\1/p" | head -n 1)
            VCODE=$(echo "$BADGING" | grep "^package:" | sed -n "s/.* versionCode='\([^']*\)'.*/\1/p" | head -n 1)
            if [ -z "$VNAME" ]; then VNAME="$VCODE"; fi
            NAME=$(echo "$LABEL" | tr -cs 'A-Za-z0-9._-' '_' | sed 's/^_*//; s/_*$//')
            if [ -z "$NAME" ]; then NAME=$(echo "${PKG##*.}" | tr -cs 'A-Za-z0-9._-' '_' | sed 's/^_*//; s/_*$//'); fi
            if [ -z "$NAME" ]; then NAME="app"; fi
            VSAFE=$(echo "$VNAME" | tr -cs 'A-Za-z0-9._-' '_' | sed 's/^_*//; s/_*$//')
            if [ -z "$VSAFE" ]; then VSAFE="0"; fi
            IDX=$((IDX+1))
            STEM="${NAME}_${VSAFE}_build${GITHUB_RUN_NUMBER}"
            if [ "$IDX" -gt 1 ]; then STEM="${STEM}_${IDX}"; fi
            NEW="$(dirname "$apk")/${STEM}.apk"
            if [ "$apk" != "$NEW" ]; then mv -f "$apk" "$NEW"; fi
            echo "APK: $NEW"
            if [ "$IDX" -eq 1 ]; then echo "artifact=$STEM" >> "$GITHUB_OUTPUT"; fi
          done < <(find . -path "*/build/outputs/apk/*" -name "*.apk")
      - name: Upload Hasil APK
        uses: actions/upload-artifact@v6
        with:
          name: ${{ steps.nama.outputs.artifact }}
          path: '**/build/outputs/apk/**/*.apk'
          if-no-files-found: error
]]
local path=".github/workflows/build.yml"
local b64=Base64.encodeToString(String(yamlContent).getBytes("UTF-8"),Base64.NO_WRAP)
say("Menyiapkan konfigurasi bangun APK...")
local function put(sha)
local body='{"message":"Setup otomatis GitHub Actions untuk kompilasi ZIP/APK","content":"'..b64..'"'
if sha and sha~="" then body=body..',"sha":"'..sha..'"' end
body=body.."}"
ghRequest("PUT",contentsUrl(repoFullName,path),body,function(code,res)
if code==200 or code==201 then
say("Konfigurasi bangun APK siap.")
if onReady then onReady() end
else say("Gagal menyiapkan konfigurasi. "..errInfo(code,res)) end
end)
end
ghRequest("GET",contentsUrl(repoFullName,path),nil,function(code,res)
if code==200 then
local o=jobj(res)
local cur=""
if o and not o.isNull("content") then cur=(tostring(o.getString("content")):gsub("%s","")) end
local sha="" if o then sha=tostring(o.optString("sha","")) end
if cur==b64 then
if onReady then onReady() end
else put(sha) end
elseif code==404 then put(nil)
else say("Gagal memeriksa konfigurasi. "..errInfo(code,res)) end
end)
end
uploadSecretApi=function(repoFullName,secretName,secretValue,isBase64,onComplete)
Thread(Runnable{run=function() local ok,err=pcall(function()
local pkConn=URL("https://api.github.com/repos/"..repoFullName.."/actions/secrets/public-key").openConnection()
pkConn.setRequestProperty("Authorization","Bearer "..token) pkConn.setRequestProperty("Accept","application/vnd.github.v3+json")
if pkConn.getResponseCode()==200 then
local reader=BufferedReader(InputStreamReader(pkConn.getInputStream()))
local res="" local line=reader.readLine()
while line do res=res..line line=reader.readLine() end reader.close() pkConn.disconnect()
local keyId=res:match('"key_id"%s*:%s*"([^"]+)"')
local pubKey=res:match('"key"%s*:%s*"([^"]+)"')
if keyId and pubKey then
local gasConn=URL(gasUrl).openConnection()
gasConn.setRequestMethod("POST") gasConn.setRequestProperty("Content-Type","application/json") gasConn.setDoOutput(true)
local isB64Str="false" if isBase64 then isB64Str="true" end
local valEscaped=secretValue:gsub("\\","\\\\"):gsub('"','\\"')
local payload='{"token":"'..token..'","repo":"'..repoFullName..'","public_key":"'..pubKey..'","key_id":"'..keyId..'","secret_name":"'..secretName..'","secret_value":"'..valEscaped..'","is_base64":'..isB64Str..'}'
local writer=OutputStreamWriter(gasConn.getOutputStream()) writer.write(payload) writer.flush() writer.close()
local gCode=gasConn.getResponseCode() local gRes=""
local gReader=BufferedReader(InputStreamReader(gasConn.getInputStream()))
local gLine=gReader.readLine()
while gLine do gRes=gRes..gLine gLine=gReader.readLine() end gReader.close()
gasConn.disconnect()
Handler(Looper.getMainLooper()).post(Runnable{run=function()
if gCode==200 and not gRes:match('"error"') then if onComplete then onComplete(true) end
else
local errMsg=gRes:match('"error"%s*:%s*"([^"]+)"') or gRes
print("ERROR UPLOAD SECRET: " .. errMsg)
service.speak("Gagal saat unggah "..secretName..". Cek log print.")
if onComplete then onComplete(false) end end end})
else Handler(Looper.getMainLooper()).post(Runnable{run=function() service.speak("Gagal mendapatkan kunci publik repositori.") if onComplete then onComplete(false) end end}) end
else pkConn.disconnect() Handler(Looper.getMainLooper()).post(Runnable{run=function() service.speak("Gagal akses GitHub Secrets API.") if onComplete then onComplete(false) end end}) end
end)
if not ok then Handler(Looper.getMainLooper()).post(Runnable{run=function() print("ERROR SECRET SCRIPT: "..tostring(err)) service.speak("Error skrip. Silakan cek log print.") if onComplete then onComplete(false) end end}) end
end}).start() end
checkExistingSecrets=function(repoFullName,callback)
ghRequest("GET","https://api.github.com/repos/"..repoFullName.."/actions/secrets",nil,function(code,res)
if code==200 then callback(res) else callback("") end end) end
local function delSecrets(repoFullName,names,onDone)
local i=0
local function nxt()
i=i+1
if i>#names then onDone() return end
ghRequest("DELETE","https://api.github.com/repos/"..repoFullName.."/actions/secrets/"..names[i],nil,function() nxt() end)
end
nxt() end
local function putSecrets(repoFullName,list,onDone)
local i=0
local function nxt(ok)
if ok==false then return end
i=i+1
if i>#list then onDone() return end
say("Mengunggah "..list[i][1].."...")
uploadSecretApi(repoFullName,list[i][1],list[i][2],false,nxt)
end
nxt(true) end
local function fileB64(path,cb)
local f=File(path)
if not f.exists() then say("File tidak ditemukan: "..path) return end
bg(function() local ok,err=pcall(function()
local b=Base64.encodeToString(readFileBytes(f),Base64.NO_WRAP)
ui(function() cb(b) end)
end)
if not ok then ui(function() print("ERROR BACA FILE: "..tostring(err)) say("Gagal membaca file. Cek log print.") end) end
end) end
local function pickFile(layout,label)
local t=txt("Belum dipilih: "..label)
local b=mkbtn("PILIH "..label)
b.setOnClickListener(function() showFilePicker("/storage/emulated/0",function(p) t.setText(p) end) end)
layout.addView(b) layout.addView(t)
return t end
local function showKeystoreForm(repoFullName,onDone)
local d=dlg("Tanda Tangan Keystore")
local scroll=ScrollView(service) local l=vbox()
l.addView(txt("Mendukung file .jks, .keystore, .p12, .pfx, .bks, dan .jceks. Jenis file dikenali otomatis."))
local tf=pickFile(l,"FILE KEYSTORE")
local iAlias=inp("Key Alias (boleh kosong jika hanya ada satu kunci)") l.addView(iAlias)
local iSP=inp("Keystore Password") l.addView(iSP)
local iKP=inp("Key Password (kosong = sama dengan keystore password)") l.addView(iKP)
local bUp=mkbtn("SIMPAN TANDA TANGAN")
bUp.setOnClickListener(function()
local path=tostring(tf.getText())
local alias=trim(iAlias.getText())
local sp=tostring(iSP.getText())
local kp=tostring(iKP.getText()) if kp=="" then kp=sp end
if path:sub(1,1)~="/" or sp=="" then say("File keystore dan keystore password wajib diisi.") return end
fileB64(path,function(b64)
say("Membersihkan tanda tangan lama...")
delSecrets(repoFullName,{"SIGN_KEY_BASE64","SIGN_CERT_BASE64","KEY_ALIAS"},function()
local list={{"KEYSTORE_BASE64",b64},{"KEYSTORE_PASSWORD",sp},{"KEY_PASSWORD",kp}}
if alias~="" then list[#list+1]={"KEY_ALIAS",alias} end
putSecrets(repoFullName,list,function() say("Tanda tangan keystore berhasil disimpan.") d.dismiss() if onDone then onDone() end end)
end)
end)
end) l.addView(bUp)
local bBack=mkbtn("BATAL") l.addView(bBack)
scroll.addView(l) d.setView(scroll) setBackAction(d,bBack,nil) d.show() end
local function showPemForm(repoFullName,onDone)
local d=dlg("Tanda Tangan Kunci + Sertifikat")
local scroll=ScrollView(service) local l=vbox()
l.addView(txt("Kunci privat: .pk8, .pem, atau .key. Sertifikat: .pem, .crt, .cer, atau .der."))
local tk=pickFile(l,"FILE KUNCI PRIVAT")
local tc=pickFile(l,"FILE SERTIFIKAT")
local iKP=inp("Password kunci (hanya jika kunci PEM terenkripsi)") l.addView(iKP)
local bUp=mkbtn("SIMPAN TANDA TANGAN")
bUp.setOnClickListener(function()
local kpath=tostring(tk.getText())
local cpath=tostring(tc.getText())
local kp=tostring(iKP.getText())
if kpath:sub(1,1)~="/" or cpath:sub(1,1)~="/" then say("File kunci dan sertifikat wajib dipilih.") return end
fileB64(kpath,function(kb)
fileB64(cpath,function(cb2)
say("Membersihkan tanda tangan lama...")
delSecrets(repoFullName,{"KEYSTORE_BASE64","KEYSTORE_PASSWORD","KEY_ALIAS","KEY_PASSWORD"},function()
local list={{"SIGN_KEY_BASE64",kb},{"SIGN_CERT_BASE64",cb2}}
if kp~="" then list[#list+1]={"KEY_PASSWORD",kp} end
putSecrets(repoFullName,list,function() say("Tanda tangan kunci dan sertifikat berhasil disimpan.") d.dismiss() if onDone then onDone() end end)
end)
end)
end)
end) l.addView(bUp)
local bBack=mkbtn("BATAL") l.addView(bBack)
scroll.addView(l) d.setView(scroll) setBackAction(d,bBack,nil) d.show() end
showSecretManager=function(repoFullName)
local sDialog=dlg("Kelola Tanda Tangan")
local scroll=ScrollView(service) local layout=vbox()
local txtStatus=txt("Memeriksa status tanda tangan...") txtStatus.setPadding(0,0,0,20) layout.addView(txtStatus)
local function refresh()
checkExistingSecrets(repoFullName,function(res)
if res:find('"SIGN_KEY_BASE64"',1,true) then txtStatus.setText("Status: terpasang tanda tangan kunci + sertifikat.")
elseif res:find('"KEYSTORE_BASE64"',1,true) then txtStatus.setText("Status: terpasang tanda tangan keystore.")
else txtStatus.setText("Status: belum ada tanda tangan. Build memakai tanda tangan debug standar.") end
end) end
refresh()
local bKs=mkbtn("TAMBAH / GANTI TANDA TANGAN: KEYSTORE") bKs.setOnClickListener(function() showKeystoreForm(repoFullName,refresh) end) layout.addView(bKs)
local bPem=mkbtn("TAMBAH / GANTI TANDA TANGAN: KUNCI + SERTIFIKAT") bPem.setOnClickListener(function() showPemForm(repoFullName,refresh) end) layout.addView(bPem)
local bDel=mkbtn("HAPUS TANDA TANGAN")
bDel.setOnClickListener(function()
confirmDialog("Hapus Tanda Tangan","Hapus semua data tanda tangan dari repositori ini? Build berikutnya memakai tanda tangan debug standar.","YA, HAPUS",function()
say("Menghapus tanda tangan...")
delSecrets(repoFullName,{"KEYSTORE_BASE64","KEYSTORE_PASSWORD","KEY_ALIAS","KEY_PASSWORD","SIGN_KEY_BASE64","SIGN_CERT_BASE64"},function() say("Tanda tangan dihapus.") refresh() end)
end)
end) layout.addView(bDel)
local btnBack=mkbtn("KEMBALI") layout.addView(btnBack)
scroll.addView(layout) sDialog.setView(scroll) setBackAction(sDialog,btnBack,nil) sDialog.show() end
local function showInstallDialog(paths,repoFullName)
local d=dlg("Instal APK")
local l=vbox()
l.addView(txt("APK berhasil diunduh ke folder Download. Mau menginstalnya sekarang?"))
for _,p in ipairs(paths) do
local b=mkbtn("INSTAL: "..p:match("([^/]+)$"))
b.setOnClickListener(function()
if repoFullName then closeAllAndResume("REPOCONTENT|"..repoFullName.."|"..(repoFullName:match("/([^/]+)$") or repoFullName).."|") else d.dismiss() end
service.installApk(p)
end) l.addView(b)
end
local bNo=mkbtn("NANTI SAJA") l.addView(bNo)
d.setView(l) setBackAction(d,bNo,nil) d.show() end
downloadArtifact=function(downloadUrl,artifactName,onSaved,repoFullName)
say("Mengunduh dan mengekstrak APK. Mohon tunggu...")
bg(function() local ok,err=pcall(function()
local conn=URL(downloadUrl).openConnection()
conn.setRequestProperty("Authorization","Bearer "..token) conn.setInstanceFollowRedirects(false)
conn.setConnectTimeout(15000) conn.setReadTimeout(60000)
local code=conn.getResponseCode()
local finalUrl=downloadUrl
if code==302 or code==301 then finalUrl=conn.getHeaderField("Location") end
conn.disconnect()
local dlConn=URL(finalUrl).openConnection()
dlConn.setConnectTimeout(15000) dlConn.setReadTimeout(60000)
if finalUrl==downloadUrl then dlConn.setRequestProperty("Authorization","Bearer "..token) end
local zin=ZipInputStream(dlConn.getInputStream())
local outDir=File("/storage/emulated/0/Download")
if not outDir.exists() then outDir.mkdirs() end
local saved={}
local paths={}
local buffer=Array.newInstance(Byte.TYPE,8192)
local entry=zin.getNextEntry()
while entry do
local ename=tostring(entry.getName())
if (not entry.isDirectory()) and ename:lower():match("%.apk$") then
local base=ename:match("([^/]+)$") or (artifactName..".apk")
local outPath="/storage/emulated/0/Download/"..base
local fos=FileOutputStream(File(outPath))
local n=zin.read(buffer)
while n~=-1 do fos.write(buffer,0,n) n=zin.read(buffer) end
fos.flush() fos.close()
table.insert(saved,base) table.insert(paths,outPath) end
zin.closeEntry()
entry=zin.getNextEntry() end
zin.close() dlConn.disconnect()
ui(function()
if #saved==0 then say("Tidak ada file APK di dalam hasil build ini.")
else say("Berhasil! "..#saved.." APK tersimpan di folder Download: "..table.concat(saved,", ")) if onSaved then onSaved(paths) else showInstallDialog(paths,repoFullName) end end end)
end)
if not ok then ui(function()
print("ERROR DOWNLOAD ARTIFACT:\n"..tostring(err))
say("Gagal mengunduh. Log error telah dicetak. Silakan salin log tersebut.") end) end
end) end
local function findReleaseByTag(repo,tag,cb)
ghRequest("GET","https://api.github.com/repos/"..repo.."/releases/tags/"..encodeURI(tag),nil,function(c,r)
if c==200 then cb(jobj(r)) return end
ghRequest("GET","https://api.github.com/repos/"..repo.."/releases?per_page=100",nil,function(c2,r2)
local arr=nil
if c2==200 then arr=jarr(r2) end
if arr then
for i=0,arr.length()-1 do
local o=arr.getJSONObject(i)
if tostring(o.optString("tag_name",""))==tag then cb(o) return end
end
end
cb(nil)
end)
end)
end
local function publishApkToRelease(repoFullName,aUrl,aName)
downloadArtifact(aUrl,aName,function(paths)
local fname=paths[1]:match("([^/]+)$") or ""
local ver,bn=fname:match("_([^_/]+)_build(%d+)")
local defTag=nil
if ver then defTag="v"..ver.."-build"..bn else local v2=fname:match("_([^_/]+)%.apk$") if v2 then defTag="v"..v2 end end
local d=dlg("Terbitkan ke Release")
local scroll=ScrollView(service) local l=vbox()
l.addView(txt("Jumlah APK yang akan diunggah: "..#paths..". Hanya repositori publik yang ditampilkan sebagai tujuan, karena release di repositori privat tidak bisa diunduh umum."))
local target=nil
local publicRepos={}
local bRepo=mkbtn("MEMUAT DAFTAR REPOSITORI PUBLIK...")
local function setLabel()
if target then bRepo.setText("REPOSITORI TUJUAN: "..target.." (ketuk untuk ganti)") else bRepo.setText("PILIH REPOSITORI PUBLIK TUJUAN") end
end
ghRequest("GET","https://api.github.com/user/repos?visibility=public&affiliation=owner,collaborator,organization_member&sort=pushed&per_page=100",nil,function(code,res)
local arr=nil
if code==200 then arr=jarr(res) end
if arr then
for i=0,arr.length()-1 do
local o=arr.getJSONObject(i)
local perm=o.optJSONObject("permissions")
if not o.optBoolean("private",false) and not o.optBoolean("archived",false) and (not perm or perm.optBoolean("push",false)) then
local n=tostring(o.optString("full_name",""))
publicRepos[#publicRepos+1]=n
if n==repoFullName then target=n end
end
end
end
if #publicRepos==0 then bRepo.setText("TIDAK ADA REPOSITORI PUBLIK TERSEDIA") else setLabel() end
end)
bRepo.setOnClickListener(function()
if #publicRepos==0 then say("Tidak ada repositori publik yang tersedia.") return end
local pd=dlg("Pilih Repositori Publik")
local ps=ScrollView(service) local pl=vbox()
for _,n in ipairs(publicRepos) do
local b=mkbtn(n)
b.setOnClickListener(function() target=n setLabel() pd.dismiss() say("Dipilih: "..n) end) pl.addView(b)
end
local bC=mkbtn("BATAL") pl.addView(bC)
ps.addView(pl) pd.setView(ps) setBackAction(pd,bC,nil) pd.show()
end) l.addView(bRepo)
local iTag=inp("Tag (misal: v1.0.0)") if defTag then iTag.setText(defTag) end l.addView(iTag)
local iName=inp("Judul release (kosong = sama dengan tag)") l.addView(iName)
local iBody=inp("Deskripsi (opsional)") l.addView(iBody)
local bGo=mkbtn("TERBITKAN")
bGo.setOnClickListener(function()
local dest=target
if not dest then say("Pilih repositori publik tujuan terlebih dahulu.") return end
local tag=trim(iTag.getText())
if tag=="" then say("Tag tidak boleh kosong.") return end
local name=trim(iName.getText()) if name=="" then name=tag end
d.dismiss()
local function uploadAll(relId,relUrl)
local idx=0
local function nextUp()
idx=idx+1
if idx>#paths then service.copy(relUrl) say("APK berhasil diterbitkan ke release "..dest..". Alamat release disalin.") return end
uploadAssetApi(dest,relId,paths[idx],nextUp)
end
nextUp()
end
local body='{"tag_name":"'..esc(tag)..'","name":"'..esc(name)..'","body":"'..esc(tostring(iBody.getText()))..'"}'
say("Membuat release di "..dest.."...")
ghRequest("POST","https://api.github.com/repos/"..dest.."/releases",body,function(code,res)
if code==201 then
local o=jobj(res)
uploadAll(num(o.getLong("id")),tostring(o.optString("html_url","")))
elseif code==422 then
findReleaseByTag(dest,tag,function(o)
if o then uploadAll(num(o.getLong("id")),tostring(o.optString("html_url",""))) else say("Gagal membuat release. "..errInfo(code,res)) end
end)
else
say("Gagal membuat release. "..errInfo(code,res))
end
end)
end) l.addView(bGo)
local bBack=mkbtn("BATAL") l.addView(bBack)
scroll.addView(l) d.setView(scroll) setBackAction(d,bBack,nil) d.show()
end)
end
fetchRunArtifacts=function(repoFullName,runId)
say("Mengecek ketersediaan APK dari server...")
ghRequest("GET","https://api.github.com/repos/"..repoFullName.."/actions/runs/"..runId.."/artifacts",nil,function(code,res)
if code~=200 then say("Gagal mengecek artifact. "..errInfo(code,res)) return end
local aDialog=dlg("Hasil Build APK")
local scroll=ScrollView(service)
local l=vbox()
local o=jobj(res)
local arr=o and o.optJSONArray("artifacts")
local shown=0
if arr then
for i=0,arr.length()-1 do
local a=arr.getJSONObject(i)
local aName=tostring(a.optString("name","artifact"))
local aUrl=tostring(a.optString("archive_download_url",""))
local aId=num(a.getLong("id"))
if aUrl~="" and not a.optBoolean("expired",false) then
shown=shown+1
local kb=string.format("%.0f",a.optLong("size_in_bytes",0)/1024)
local bDown=mkbtn("UNDUH APK: "..aName.." ("..kb.." KB)")
bDown.setOnClickListener(function() aDialog.dismiss() downloadArtifact(aUrl,aName,nil,repoFullName) end) l.addView(bDown)
local bPub=mkbtn("TERBITKAN KE RELEASE: "..aName)
bPub.setOnClickListener(function() aDialog.dismiss() publishApkToRelease(repoFullName,aUrl,aName) end) l.addView(bPub)
local bDel=mkbtn("HAPUS ARTEFAK: "..aName)
bDel.setOnClickListener(function()
confirmDialog("Hapus Artefak","Hapus artefak "..aName.."? File APK di server akan hilang.","YA, HAPUS",function()
ghRequest("DELETE","https://api.github.com/repos/"..repoFullName.."/actions/artifacts/"..aId,nil,function(c,r)
if c==204 then say("Artefak terhapus.") aDialog.dismiss() fetchRunArtifacts(repoFullName,runId)
else say("Gagal menghapus artefak. "..errInfo(c,r)) end
end)
end)
end) l.addView(bDel)
end
end
end
if shown==0 then
local t=txt("Tidak ada APK/Artifact yang tersedia dari build ini. Mungkin masih proses kompilasi, sudah kedaluwarsa, sudah dihapus, atau terjadi error di kode sumber (gradle) Anda.") l.addView(t) end
local bBack=mkbtn("TUTUP") l.addView(bBack)
scroll.addView(l) aDialog.setView(scroll) setBackAction(aDialog,bBack,nil) aDialog.show() end) end
local function showLogDialog(title,text)
local d=dlg(title)
local scroll=ScrollView(service)
local l=vbox()
local bCopy=mkbtn("SALIN SEMUA LOG")
bCopy.setOnClickListener(function() service.copy(text) say("Log berhasil disalin.") end) l.addView(bCopy)
local t=txt(text) pcall(function() t.setTextIsSelectable(true) end) l.addView(t)
local bBack=mkbtn("TUTUP") l.addView(bBack)
scroll.addView(l) d.setView(scroll) setBackAction(d,bBack,nil) d.show() end
local function fetchJobLog(repoFullName,jobId,cb)
bg(function() local ok,err=pcall(function()
local c=URL("https://api.github.com/repos/"..repoFullName.."/actions/jobs/"..jobId.."/logs").openConnection()
c.setRequestProperty("Authorization","Bearer "..token) c.setInstanceFollowRedirects(false)
c.setConnectTimeout(15000) c.setReadTimeout(30000)
local code=c.getResponseCode()
local loc=nil
if code==302 or code==301 then loc=c.getHeaderField("Location") end
c.disconnect()
if not loc then ui(function() cb(false,"Log belum tersedia. Kode "..tostring(code)) end) return end
local c2=URL(loc).openConnection() c2.setConnectTimeout(15000) c2.setReadTimeout(60000)
local r=BufferedReader(InputStreamReader(c2.getInputStream(),"UTF-8"))
local tail,errs={},{}
local ctx=0
local line=r.readLine()
while line do
line=(tostring(line):gsub("^%d%d%d%d%-%d%d%-%d%dT[%d:%.]+Z ",""))
local isStack=(line:match("^%s+at ")~=nil) or (line:match("^%s*%.%.%. %d+ more")~=nil)
if not isStack then
if line:find("What went wrong",1,true) then ctx=10 end
if #errs<80 and (ctx>0 or line:find("##[error]",1,true) or line:find("error:",1,true) or line:find("Caused by:",1,true) or line:find("Execution failed",1,true)) then errs[#errs+1]=line end
if ctx>0 then ctx=ctx-1 end
tail[#tail+1]=line if #tail>80 then table.remove(tail,1) end
end
line=r.readLine() end
r.close() c2.disconnect()
local text="== BARIS ERROR ==\n"..table.concat(errs,"\n").."\n\n== 80 BARIS TERAKHIR (tanpa stack trace) ==\n"..table.concat(tail,"\n")
ui(function() cb(true,text) end)
end)
if not ok then ui(function() print("ERROR AMBIL LOG: "..tostring(err)) say("Gagal mengambil log. Cek log print.") end) end
end) end
local function concl(x) if x.isNull("conclusion") then return "" end return tostring(x.optString("conclusion","")) end
local function showRunErrorLog(repoFullName,runId)
say("Mencari langkah yang gagal...")
ghRequest("GET","https://api.github.com/repos/"..repoFullName.."/actions/runs/"..runId.."/jobs",nil,function(code,res)
if code~=200 then say("Gagal memuat job. "..errInfo(code,res)) return end
local o=jobj(res)
local jobs=o and o.optJSONArray("jobs")
if not jobs or jobs.length()==0 then say("Belum ada job untuk build ini.") return end
local pick=jobs.getJSONObject(0)
for i=0,jobs.length()-1 do local j=jobs.getJSONObject(i) if concl(j)=="failure" then pick=j break end end
local jobId=num(pick.getLong("id"))
local stepName=""
local steps=pick.optJSONArray("steps")
if steps then for k=0,steps.length()-1 do local st=steps.getJSONObject(k) if concl(st)=="failure" then stepName=tostring(st.optString("name","")) break end end end
if stepName~="" then say("Langkah yang gagal: "..stepName..". Mengambil log...") else say("Mengambil log...") end
fetchJobLog(repoFullName,jobId,function(okLog,text)
if okLog then
text="LANGKAH GAGAL: "..(stepName~="" and stepName or "tidak diketahui").."\n\n"..text
print(text)
showLogDialog("Log Error Build "..runId,text)
else say(text) end end) end) end
showWorkflowRuns=function(repoFullName,repoName,resJson)
local rDialog=dlg("Riwayat Build: "..repoName)
local scroll=ScrollView(service) local layout=vbox()
local doneIds={}
local function reload() rDialog.dismiss() fetchWorkflowRuns(repoFullName,repoName) end
local btnRefresh=mkbtn("SEGARKAN") btnRefresh.setOnClickListener(function() reload() end) layout.addView(btnRefresh)
local btnAll=mkbtn("HAPUS SEMUA CATATAN BUILD")
btnAll.setOnClickListener(function()
if #doneIds==0 then say("Tidak ada catatan build yang bisa dihapus.") return end
confirmDialog("Hapus Semua Catatan Build","Hapus "..#doneIds.." catatan build yang sudah selesai beserta artefaknya?","YA, HAPUS SEMUA",function()
local idx=0
local function nextDel()
idx=idx+1
if idx>#doneIds then say("Semua catatan build selesai dihapus.") reload() return end
ghRequest("DELETE","https://api.github.com/repos/"..repoFullName.."/actions/runs/"..doneIds[idx],nil,function() nextDel() end)
end
say("Menghapus catatan build...")
nextDel()
end)
end) layout.addView(btnAll)
local o=jobj(resJson)
local arr=o and o.optJSONArray("workflow_runs")
local hasRun=false
if arr then
for i=0,arr.length()-1 do
local r=arr.getJSONObject(i)
hasRun=true
local runId=num(r.getLong("id"))
local status=tostring(r.optString("status",""))
local conclusion="" if not r.isNull("conclusion") then conclusion=tostring(r.optString("conclusion","")) end
local date=tostring(r.optString("created_at",""))
local displayStatus=status if conclusion~="" then displayStatus=conclusion end
local bItem=mkbtn(runId.."\nStatus: "..displayStatus.." | "..date:sub(1,10).."\nKetuk untuk CEK/UNDUH APK")
bItem.setOnClickListener(function() fetchRunArtifacts(repoFullName,runId) end) layout.addView(bItem)
if conclusion=="failure" then local bLog=mkbtn("LIHAT LOG ERROR build "..runId) bLog.setOnClickListener(function() showRunErrorLog(repoFullName,runId) end) layout.addView(bLog) end
if conclusion=="startup_failure" then local bWeb=mkbtn("BUKA PENYEBAB DI BROWSER (build "..runId..")")
bWeb.setOnClickListener(function()
local it=Intent(Intent.ACTION_VIEW,Uri.parse("https://github.com/"..repoFullName.."/actions/runs/"..runId))
it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) service.startActivity(it) end) layout.addView(bWeb) end
if status=="completed" then
doneIds[#doneIds+1]=runId
local bDel=mkbtn("HAPUS CATATAN BUILD "..runId)
bDel.setOnClickListener(function()
confirmDialog("Hapus Catatan Build","Hapus catatan build "..runId.." beserta artefaknya?","YA, HAPUS",function()
ghRequest("DELETE","https://api.github.com/repos/"..repoFullName.."/actions/runs/"..runId,nil,function(code,res)
if code==204 then say("Catatan build terhapus.") reload() else say("Gagal menghapus. "..errInfo(code,res)) end
end)
end)
end) layout.addView(bDel)
end
end
end
if not hasRun then local t=txt("Belum ada riwayat build.") layout.addView(t) end
local bBack=mkbtn("KEMBALI") layout.addView(bBack)
scroll.addView(layout) rDialog.setView(scroll) setBackAction(rDialog,bBack,nil) rDialog.show() end
fetchWorkflowRuns=function(repoFullName,repoName)
say("Memuat riwayat pemantauan build...")
ghRequest("GET","https://api.github.com/repos/"..repoFullName.."/actions/runs?per_page=15",nil,function(code,res)
if code==200 then showWorkflowRuns(repoFullName,repoName,res) else say("Gagal memuat riwayat build. "..errInfo(code,res)) end end) end
local function watchBuild(repoFullName,sinceIso)
local runId=nil
local tries=0
local base="https://api.github.com/repos/"..repoFullName.."/actions/runs"
local poll
poll=function()
tries=tries+1
if tries>180 then say("Pemantauan build dihentikan karena sudah terlalu lama.") return end
local url=base.."?per_page=5&event=workflow_dispatch"
if runId then url=base.."/"..runId end
ghRequest("GET",url,nil,function(code,res)
local run=nil
if code==200 then
local o=jobj(res)
if runId then
run=o
elseif o then
local arr=o.optJSONArray("workflow_runs")
if arr then
for i=0,arr.length()-1 do
local r=arr.getJSONObject(i)
if tostring(r.optString("created_at",""))>=sinceIso then run=r break end
end
end
if run then runId=num(run.getLong("id")) say("Build dimulai di server.") end
end
end
if run and tostring(run.optString("status",""))=="completed" then
local concl=""
if not run.isNull("conclusion") then concl=tostring(run.optString("conclusion","")) end
if concl=="success" then say("Build selesai dan berhasil.") fetchRunArtifacts(repoFullName,runId)
elseif concl=="cancelled" then say("Build dibatalkan.")
else say("Build selesai dengan status "..concl..". Buka Pemantauan Build lalu pilih Lihat Log Error.") end
else
mainH.postDelayed(Runnable{run=poll},15000)
end
end)
end
mainH.postDelayed(Runnable{run=poll},10000)
end
dispatchWorkflowApi=function(repoFullName,wfId,inputsJson)
say("Memulai bangun APK...")
local sinceIso=os.date("!%Y-%m-%dT%H:%M:%SZ",os.time()-60)
local attempts=0
ghRequest("GET","https://api.github.com/repos/"..repoFullName,nil,function(c0,r0)
if c0~=200 then say("Gagal membaca repositori. "..errInfo(c0,r0)) return end
local ref=tostring(jobj(r0).optString("default_branch","main"))
local body='{"ref":"'..esc(ref)..'"'
if inputsJson then body=body..',"inputs":'..inputsJson end
body=body.."}"
local function tryDispatch()
attempts=attempts+1
ghRequest("POST","https://api.github.com/repos/"..repoFullName.."/actions/workflows/"..wfId.."/dispatches",body,function(code,res)
if code==204 then
say("Bangun APK dimulai. Anda akan diberi tahu lewat suara saat selesai.")
watchBuild(repoFullName,sinceIso)
elseif (code==404 or code==422) and attempts<4 then
mainH.postDelayed(Runnable{run=tryDispatch},4000)
else
say("Gagal memulai build. "..errInfo(code,res))
end
end)
end
tryDispatch()
end)
end
showWorkflowsList=function(repoFullName,repoName,resJson)
local o=jobj(resJson)
local arr=o and o.optJSONArray("workflows")
local items={}
local hasBuild=false
if arr then
for i=0,arr.length()-1 do
local w=arr.getJSONObject(i)
local path=tostring(w.optString("path",""))
if path:find("build.yml",1,true) then hasBuild=true end
if tostring(w.optString("state",""))=="active" then
items[#items+1]={id=num(w.getLong("id")),name=tostring(w.optString("name","")),path=path}
end
end
end
if not hasBuild then table.insert(items,1,{id="build.yml",name="Bangun APK Otomatis",path=".github/workflows/build.yml"}) end
local prefFile=baseDir.."gh_build_pref.txt"
local r8on,signon=false,true
local pf=io.open(prefFile,"r")
if pf then local a,b=pf:read("*all"):match("(%d)|(%d)") pf:close() if a then r8on=(a=="1") signon=(b=="1") end end
local wDialog=dlg("Bangun APK: "..repoName)
local scroll=ScrollView(service) local layout=vbox()
local cR8=CheckBox(service) cR8.setText("Aktifkan R8 (perkecil dan kaburkan kode, hasilnya build release)") cR8.setChecked(r8on) layout.addView(cR8)
local cSign=CheckBox(service) cSign.setText("Tanda tangani dengan kunci pribadi saya (jika sudah diatur di Kelola Tanda Tangan)") cSign.setChecked(signon) layout.addView(cSign)
layout.addView(txt("Catatan: R8 bisa merusak aplikasi yang memakai refleksi. Build release tanpa kunci pribadi ditandatangani dengan kunci debug sementara."))
for _,w in ipairs(items) do
local b=mkbtn("BANGUN: "..w.name.."\n"..w.path)
b.setOnClickListener(function()
local r8=cR8.isChecked() local sg=cSign.isChecked()
local wf=io.open(prefFile,"w") if wf then wf:write((r8 and "1" or "0").."|"..(sg and "1" or "0")) wf:close() end
local inputs=nil
if w.path:find("build.yml",1,true) then inputs='{"r8":"'..tostring(r8)..'","sign":"'..tostring(sg)..'"}' end
wDialog.dismiss() dispatchWorkflowApi(repoFullName,w.id,inputs) end) layout.addView(b)
end
local bBack=mkbtn("KEMBALI") layout.addView(bBack)
scroll.addView(layout) wDialog.setView(scroll) setBackAction(wDialog,bBack,nil) wDialog.show() end
fetchWorkflows=function(repoFullName,repoName)
say("Memuat daftar bangun APK...")
ghRequest("GET","https://api.github.com/repos/"..repoFullName.."/actions/workflows",nil,function(code,res)
if code==200 then showWorkflowsList(repoFullName,repoName,res) else say("Gagal memuat daftar. "..errInfo(code,res)) end end) end
local relListDlg=nil
local function reloadReleases(repoFullName,repoName)
if relListDlg then pcall(function() relListDlg.dismiss() end) relListDlg=nil end
fetchReleases(repoFullName,repoName) end
deleteReleaseApi=function(repoFullName,relId,onDone)
say("Menghapus release...")
ghRequest("DELETE","https://api.github.com/repos/"..repoFullName.."/releases/"..relId,nil,function(code,res)
if code==204 then say("Release terhapus.") if onDone then onDone() end
else say("Gagal menghapus release. "..errInfo(code,res)) end end) end
uploadAssetApi=function(repoFullName,relId,localPath,onDone)
local f=File(localPath)
if not f.exists() then say("File tidak ditemukan.") return end
say("Membaca dan mengunggah aset. Mohon tunggu...")
bg(function() local ok,err=pcall(function()
local bytes=readFileBytes(f)
local fname=tostring(f.getName())
local c=URL("https://uploads.github.com/repos/"..repoFullName.."/releases/"..relId.."/assets?name="..encodeURI(fname)).openConnection()
c.setConnectTimeout(15000) c.setReadTimeout(120000)
c.setRequestMethod("POST")
c.setRequestProperty("Authorization","Bearer "..token) c.setRequestProperty("Accept","application/vnd.github+json")
c.setRequestProperty("Content-Type","application/octet-stream") c.setDoOutput(true)
local outs=c.getOutputStream() outs.write(bytes) outs.flush() outs.close()
local code=c.getResponseCode()
local res=readAll((code<400) and c.getInputStream() or c.getErrorStream())
c.disconnect()
ui(function()
if code==201 then say("Aset berhasil diunggah.") if onDone then onDone() end
else say("Gagal mengunggah aset. "..errInfo(code,res)) end end)
end)
if not ok then ui(function() print("ERROR UNGGAH ASET: "..tostring(err)) say("Error. Cek log print.") end) end
end) end
showManageAssets=function(repoFullName,repoName,rel,parentDialog)
local mDlg=dlg("Aset Release: "..rel.tag)
local scroll=ScrollView(service)
local l=vbox()
local function finish() mDlg.dismiss() if parentDialog then parentDialog.dismiss() end reloadReleases(repoFullName,repoName) end
local btnUp=mkbtn("UNGGAH ASET BARU")
btnUp.setOnClickListener(function()
showFilePicker("/storage/emulated/0",function(p) uploadAssetApi(repoFullName,rel.id,p,finish) end) end) l.addView(btnUp)
local arr=jarr(rel.assets)
if arr then
for i=0,arr.length()-1 do
local a=arr.getJSONObject(i)
local aId=num(a.getLong("id"))
local aName=tostring(a.optString("name",""))
local kb=string.format("%.0f",a.optLong("size",0)/1024)
local aUrl=tostring(a.optString("browser_download_url",""))
if aUrl~="" then local bc=mkbtn("SALIN ALAMAT UNDUH: "..aName) bc.setOnClickListener(function() service.copy(aUrl) say("Alamat unduh berhasil disalin.") end) l.addView(bc) end
local b=mkbtn("HAPUS ASET: "..aName.." ("..kb.." KB)")
b.setOnClickListener(function()
confirmDialog("Hapus Aset","Yakin menghapus aset "..aName.."?","YA, HAPUS",function()
ghRequest("DELETE","https://api.github.com/repos/"..repoFullName.."/releases/assets/"..aId,nil,function(code,res)
if code==204 then say("Aset terhapus.") finish()
else say("Gagal menghapus aset. "..errInfo(code,res)) end end) end) end) l.addView(b) end end
local bBack=mkbtn("KEMBALI") l.addView(bBack)
scroll.addView(l) mDlg.setView(scroll) setBackAction(mDlg,bBack,nil) mDlg.show() end
showEditRelease=function(repoFullName,repoName,rel)
local eDlg=dlg("Release: "..rel.tag)
local scroll=ScrollView(service)
local l=vbox()
local tUrl=txt("Alamat release: "..rel.url) l.addView(tUrl)
local bCopyUrl=mkbtn("SALIN ALAMAT RELEASE")
bCopyUrl.setOnClickListener(function() service.copy(rel.url) say("Alamat release berhasil disalin.") end) l.addView(bCopyUrl)
local iTag=inp("Tag") iTag.setText(rel.tag) l.addView(iTag)
local iName=inp("Judul release") iName.setText(rel.name) l.addView(iName)
local iBody=inp("Deskripsi") iBody.setText(rel.body) l.addView(iBody)
local btnSave=mkbtn("SIMPAN PERUBAHAN")
btnSave.setOnClickListener(function()
local tag=trim(iTag.getText()) if tag=="" then say("Tag tidak boleh kosong.") return end
local body='{"tag_name":"'..esc(tag)..'","name":"'..esc(tostring(iName.getText()))..'","body":"'..esc(tostring(iBody.getText()))..'"}'
ghRequest("PATCH","https://api.github.com/repos/"..repoFullName.."/releases/"..rel.id,body,function(code,res)
if code==200 then say("Release diperbarui.") eDlg.dismiss() reloadReleases(repoFullName,repoName)
else say("Gagal memperbarui. "..errInfo(code,res)) end end) end) l.addView(btnSave)
local btnAssets=mkbtn("KELOLA ASET ("..rel.assetCount..")")
btnAssets.setOnClickListener(function() showManageAssets(repoFullName,repoName,rel,eDlg) end) l.addView(btnAssets)
local btnDel=mkbtn("HAPUS RELEASE")
btnDel.setOnClickListener(function()
confirmDialog("Hapus Release","Yakin menghapus release "..rel.tag.."? Tag git tidak ikut terhapus.","YA, HAPUS",function()
deleteReleaseApi(repoFullName,rel.id,function() eDlg.dismiss() reloadReleases(repoFullName,repoName) end) end) end) l.addView(btnDel)
local bBack=mkbtn("KEMBALI") l.addView(bBack)
scroll.addView(l) eDlg.setView(scroll) setBackAction(eDlg,bBack,nil) eDlg.show() end
showCreateRelease=function(repoFullName,repoName)
local cDlg=dlg("Buat Release Baru")
local scroll=ScrollView(service) local l=vbox()
local iTag=inp("Tag (misal: v1.0.0)") l.addView(iTag)
local iName=inp("Judul release") l.addView(iName)
local iBody=inp("Deskripsi") l.addView(iBody)
local files={}
local tFiles=txt("Aset yang akan diunggah: belum ada")
local function refreshFiles()
if #files==0 then tFiles.setText("Aset yang akan diunggah: belum ada") return end
local names={}
for i,p in ipairs(files) do names[i]=p:match("([^/]+)$") or p end
tFiles.setText("Aset yang akan diunggah ("..#files.."): "..table.concat(names,", "))
end
local bAdd=mkbtn("TAMBAH ASET")
bAdd.setOnClickListener(function()
showFilePicker("/storage/emulated/0",function(p)
for _,q in ipairs(files) do if q==p then say("File itu sudah ada di daftar aset.") return end end
files[#files+1]=p refreshFiles() say("Aset ditambahkan: "..(p:match("([^/]+)$") or p))
end)
end) l.addView(bAdd)
local bClear=mkbtn("KOSONGKAN DAFTAR ASET")
bClear.setOnClickListener(function() files={} refreshFiles() say("Daftar aset dikosongkan.") end) l.addView(bClear)
l.addView(tFiles)
local btnCreate=mkbtn("BUAT RELEASE")
btnCreate.setOnClickListener(function()
local tag=trim(iTag.getText()) if tag=="" then say("Tag tidak boleh kosong.") return end
local name=tostring(iName.getText()) if trim(name)=="" then name=tag end
local list={}
for _,p in ipairs(files) do list[#list+1]=p end
local body='{"tag_name":"'..esc(tag)..'","name":"'..esc(name)..'","body":"'..esc(tostring(iBody.getText()))..'"}'
say("Membuat release...")
ghRequest("POST","https://api.github.com/repos/"..repoFullName.."/releases",body,function(code,res)
if code~=201 then say("Gagal membuat release. "..errInfo(code,res)) return end
cDlg.dismiss()
if #list==0 then say("Release berhasil dibuat.") reloadReleases(repoFullName,repoName) return end
say("Release berhasil dibuat. Mengunggah "..#list.." aset...")
local relId=num(jobj(res).getLong("id"))
local idx=0
local function nextUp()
idx=idx+1
if idx>#list then say("Semua aset berhasil diunggah.") reloadReleases(repoFullName,repoName) return end
uploadAssetApi(repoFullName,relId,list[idx],nextUp)
end
nextUp()
end)
end) l.addView(btnCreate)
local bBack=mkbtn("BATAL") l.addView(bBack)
scroll.addView(l) cDlg.setView(scroll) setBackAction(cDlg,bBack,nil) cDlg.show() end
showReleasesList=function(repoFullName,repoName,resJson)
local rDlg=dlg("Release: "..repoFullName)
relListDlg=rDlg
local scroll=ScrollView(service)
local l=vbox()
local btnNew=mkbtn("BUAT RELEASE BARU")
btnNew.setOnClickListener(function() showCreateRelease(repoFullName,repoName) end) l.addView(btnNew)
local arr=jarr(resJson)
local shown=0
if arr then
for i=0,arr.length()-1 do
local o=arr.getJSONObject(i)
local relUrl=tostring(o.optString("html_url",""))
if relUrl=="" or relUrl:find("/"..repoFullName.."/",1,true) then
local rel={}
rel.url=relUrl
rel.id=num(o.getLong("id"))
rel.tag=tostring(o.optString("tag_name",""))
rel.name="" if not o.isNull("name") then rel.name=tostring(o.optString("name","")) end
rel.body="" if not o.isNull("body") then rel.body=tostring(o.optString("body","")) end
local assets=o.optJSONArray("assets")
rel.assets=assets and tostring(assets.toString()) or "[]"
rel.assetCount=assets and string.format("%d",assets.length()) or "0"
local label=rel.name if label=="" then label=rel.tag end
local flags=""
if o.optBoolean("draft",false) then flags=flags.." [Draft]" end
if o.optBoolean("prerelease",false) then flags=flags.." [Pra-rilis]" end
shown=shown+1
local b=mkbtn(label.."\nTag: "..rel.tag..flags.." | Aset: "..rel.assetCount)
b.setOnClickListener(function() showEditRelease(repoFullName,repoName,rel) end) l.addView(b) end end end
if shown==0 then
local t=txt("Belum ada release di repositori ini.") l.addView(t) end
local bBack=mkbtn("KEMBALI") l.addView(bBack)
scroll.addView(l) rDlg.setView(scroll) setBackAction(rDlg,bBack,nil) rDlg.show() end
fetchReleases=function(repoFullName,repoName)
say("Memuat daftar release...")
ghRequest("GET","https://api.github.com/repos/"..repoFullName.."/releases?per_page=30",nil,function(code,res)
if code==200 then showReleasesList(repoFullName,repoName,res) else say("Gagal memuat release. "..errInfo(code,res)) end end) end
local M={api=1}
M.fetchReleases=function(r,n) token=C.getToken() fetchReleases(r,n) end
M.showSecretManager=function(r) token=C.getToken() showSecretManager(r) end
M.buildApk=function(r,n) token=C.getToken() setupGithubActions(r,function() fetchWorkflows(r,n) end) end
M.fetchWorkflowRuns=function(r,n) token=C.getToken() fetchWorkflowRuns(r,n) end
return M