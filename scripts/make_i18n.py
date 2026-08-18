"""Génère les fichiers Localizable.strings (une .lproj par langue).

Langue de base : anglais. macOS choisit automatiquement la langue selon les
préférences système, avec repli sur l'anglais.

Deux sorties, une seule source :
  - i18n/<lang>.lproj/Localizable.strings — lu par l'app Swift ;
  - i18n/engine.json — lu par le moteur Python, qui n'a pas de bundle et ne peut
    donc pas passer par NSBundle. Sans lui, le moteur affichait ses invites en
    français à tout le monde.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "i18n"

# Clés servies au moteur Python (invites affichées pendant un `sudo`), par opposition
# au reste qui ne sort jamais de l'app Swift.
ENGINE_KEYS = (
    "engine.prompt.title", "engine.prompt.subtitle",
    "engine.btn.face", "engine.btn.touch", "engine.btn.password",
    "engine.touchid.reason",
)

LANGS = ["en", "fr", "es", "de", "it", "pt-BR", "nl", "ja", "zh-Hans", "ko", "ru"]

# key -> { lang: translation }
TR = {
    "app.subtitle": {
        "en": "Unlock with face recognition",
        "fr": "Déverrouillage par reconnaissance faciale",
        "es": "Desbloqueo por reconocimiento facial",
        "de": "Entsperren per Gesichtserkennung",
        "it": "Sblocco con riconoscimento facciale",
        "pt-BR": "Desbloqueio por reconhecimento facial",
        "nl": "Ontgrendelen met gezichtsherkenning",
        "ja": "顔認証でロック解除",
        "zh-Hans": "使用面容识别解锁",
        "ko": "얼굴 인식으로 잠금 해제",
        "ru": "Разблокировка по распознаванию лица",
    },
    "menu.daemon.running": {
        "en": "Daemon running", "fr": "Service actif", "es": "Servicio activo",
        "de": "Dienst aktiv", "it": "Servizio attivo", "pt-BR": "Serviço ativo",
        "nl": "Service actief", "ja": "デーモン実行中", "zh-Hans": "守护进程运行中",
        "ko": "데몬 실행 중", "ru": "Служба работает",
    },
    "menu.daemon.stopped": {
        "en": "Daemon stopped", "fr": "Service arrêté", "es": "Servicio detenido",
        "de": "Dienst gestoppt", "it": "Servizio arrestato", "pt-BR": "Serviço parado",
        "nl": "Service gestopt", "ja": "デーモン停止中", "zh-Hans": "守护进程已停止",
        "ko": "데몬 중지됨", "ru": "Служба остановлена",
    },
    "menu.enroll.setup": {
        "en": "Set Up My Face…", "fr": "Configurer mon visage…",
        "es": "Configurar mi rostro…", "de": "Mein Gesicht einrichten…",
        "it": "Configura il mio volto…", "pt-BR": "Configurar meu rosto…",
        "nl": "Mijn gezicht instellen…", "ja": "顔を設定…",
        "zh-Hans": "设置我的面容…", "ko": "내 얼굴 설정…",
        "ru": "Настроить моё лицо…",
    },
    "menu.enroll.reenroll": {
        "en": "Re-enroll My Face…", "fr": "Ré-enregistrer mon visage…",
        "es": "Volver a registrar mi rostro…", "de": "Gesicht neu erfassen…",
        "it": "Registra di nuovo il volto…", "pt-BR": "Registrar rosto novamente…",
        "nl": "Gezicht opnieuw vastleggen…", "ja": "顔を再登録…",
        "zh-Hans": "重新录入我的面容…", "ko": "내 얼굴 다시 등록…",
        "ru": "Перерегистрировать лицо…",
    },
    "menu.test": {
        "en": "Test Recognition", "fr": "Tester la reconnaissance",
        "es": "Probar el reconocimiento", "de": "Erkennung testen",
        "it": "Prova il riconoscimento", "pt-BR": "Testar reconhecimento",
        "nl": "Herkenning testen", "ja": "認識をテスト",
        "zh-Hans": "测试识别", "ko": "인식 테스트", "ru": "Проверить распознавание",
    },
    "menu.daemon.start": {
        "en": "Start Daemon", "fr": "Démarrer le service", "es": "Iniciar servicio",
        "de": "Dienst starten", "it": "Avvia servizio", "pt-BR": "Iniciar serviço",
        "nl": "Service starten", "ja": "デーモンを開始", "zh-Hans": "启动守护进程",
        "ko": "데몬 시작", "ru": "Запустить службу",
    },
    "menu.daemon.stop": {
        "en": "Stop Daemon", "fr": "Arrêter le service", "es": "Detener servicio",
        "de": "Dienst stoppen", "it": "Arresta servizio", "pt-BR": "Parar serviço",
        "nl": "Service stoppen", "ja": "デーモンを停止", "zh-Hans": "停止守护进程",
        "ko": "데몬 중지", "ru": "Остановить службу",
    },
    "menu.settings": {
        "en": "Settings…", "fr": "Réglages…", "es": "Ajustes…",
        "de": "Einstellungen…", "it": "Impostazioni…", "pt-BR": "Ajustes…",
        "nl": "Instellingen…", "ja": "設定…", "zh-Hans": "设置…",
        "ko": "설정…", "ru": "Настройки…",
    },
    "menu.update": {
        "en": "Check for Updates…", "fr": "Rechercher les mises à jour…",
        "es": "Buscar actualizaciones…", "de": "Nach Updates suchen…",
        "it": "Verifica aggiornamenti…", "pt-BR": "Buscar atualizações…",
        "nl": "Controleren op updates…", "ja": "アップデートを確認…",
        "zh-Hans": "检查更新…", "ko": "업데이트 확인…",
        "ru": "Проверить обновления…",
    },
    "menu.login": {
        "en": "Launch at Login", "fr": "Lancer au démarrage",
        "es": "Abrir al iniciar sesión", "de": "Beim Anmelden öffnen",
        "it": "Avvia all'accesso", "pt-BR": "Abrir ao iniciar sessão",
        "nl": "Openen bij inloggen", "ja": "ログイン時に起動",
        "zh-Hans": "登录时启动", "ko": "로그인 시 실행",
        "ru": "Запускать при входе",
    },
    "menu.quit": {
        "en": "Quit Mugshot", "fr": "Quitter Mugshot", "es": "Salir de Mugshot",
        "de": "Mugshot beenden", "it": "Esci da Mugshot", "pt-BR": "Sair do Mugshot",
        "nl": "Mugshot afsluiten", "ja": "Mugshotを終了", "zh-Hans": "退出 Mugshot",
        "ko": "Mugshot 종료", "ru": "Завершить Mugshot",
    },
    "notify.test.title": {
        "en": "Face ID Test", "fr": "Test Face ID", "es": "Prueba de Face ID",
        "de": "Face-ID-Test", "it": "Test Face ID", "pt-BR": "Teste do Face ID",
        "nl": "Face ID-test", "ja": "Face IDテスト", "zh-Hans": "Face ID 测试",
        "ko": "Face ID 테스트", "ru": "Тест Face ID",
    },
    "notify.test.ok": {
        "en": "Recognized ✓", "fr": "Reconnu ✓", "es": "Reconocido ✓",
        "de": "Erkannt ✓", "it": "Riconosciuto ✓", "pt-BR": "Reconhecido ✓",
        "nl": "Herkend ✓", "ja": "認識されました ✓", "zh-Hans": "已识别 ✓",
        "ko": "인식됨 ✓", "ru": "Распознано ✓",
    },
    "notify.test.fail": {
        "en": "Not recognized", "fr": "Non reconnu", "es": "No reconocido",
        "de": "Nicht erkannt", "it": "Non riconosciuto", "pt-BR": "Não reconhecido",
        "nl": "Niet herkend", "ja": "認識されませんでした", "zh-Hans": "未识别",
        "ko": "인식되지 않음", "ru": "Не распознано",
    },
    "onb.title": {
        "en": "Set Up Face ID", "fr": "Configurer Face ID",
        "es": "Configurar Face ID", "de": "Face ID einrichten",
        "it": "Configura Face ID", "pt-BR": "Configurar o Face ID",
        "nl": "Face ID instellen", "ja": "Face IDを設定",
        "zh-Hans": "设置 Face ID", "ko": "Face ID 설정", "ru": "Настройка Face ID",
    },
    "onb.intro": {
        "en": "We'll register your face to unlock sudo. It only takes a few seconds.",
        "fr": "On va enregistrer ton visage pour déverrouiller sudo. Ça prend quelques secondes.",
        "es": "Registraremos tu rostro para desbloquear sudo. Solo toma unos segundos.",
        "de": "Wir erfassen dein Gesicht, um sudo zu entsperren. Das dauert nur wenige Sekunden.",
        "it": "Registreremo il tuo volto per sbloccare sudo. Bastano pochi secondi.",
        "pt-BR": "Vamos registrar seu rosto para desbloquear o sudo. Leva só alguns segundos.",
        "nl": "We leggen je gezicht vast om sudo te ontgrendelen. Het duurt maar een paar seconden.",
        "ja": "sudoのロックを解除するために顔を登録します。数秒で完了します。",
        "zh-Hans": "我们将录入你的面容以解锁 sudo，只需几秒钟。",
        "ko": "sudo 잠금을 해제하기 위해 얼굴을 등록합니다. 몇 초면 됩니다.",
        "ru": "Мы зарегистрируем ваше лицо для разблокировки sudo. Это займёт несколько секунд.",
    },
    "onb.tip.light": {
        "en": "Face the webcam in good lighting.",
        "fr": "Place-toi face à la webcam, bien éclairé.",
        "es": "Colócate frente a la cámara con buena luz.",
        "de": "Blicke bei guter Beleuchtung in die Webcam.",
        "it": "Mettiti davanti alla webcam con buona luce.",
        "pt-BR": "Fique de frente para a webcam com boa iluminação.",
        "nl": "Kijk in de webcam bij goed licht.",
        "ja": "明るい場所でカメラに顔を向けてください。",
        "zh-Hans": "在光线充足处正对摄像头。",
        "ko": "밝은 곳에서 웹캠을 바라보세요.",
        "ru": "Смотрите в камеру при хорошем освещении.",
    },
    "onb.tip.move": {
        "en": "Move your head slightly during capture.",
        "fr": "Bouge légèrement la tête pendant la capture.",
        "es": "Mueve un poco la cabeza durante la captura.",
        "de": "Bewege den Kopf während der Aufnahme leicht.",
        "it": "Muovi leggermente la testa durante l'acquisizione.",
        "pt-BR": "Mova a cabeça levemente durante a captura.",
        "nl": "Beweeg je hoofd licht tijdens het vastleggen.",
        "ja": "撮影中は少し頭を動かしてください。",
        "zh-Hans": "采集时轻轻转动头部。",
        "ko": "촬영 중 머리를 살짝 움직이세요.",
        "ru": "Слегка поворачивайте голову во время съёмки.",
    },
    "onb.tip.local": {
        "en": "Everything stays on your Mac.",
        "fr": "Tout reste en local sur ton Mac.",
        "es": "Todo se queda en tu Mac.",
        "de": "Alles bleibt auf deinem Mac.",
        "it": "Tutto resta sul tuo Mac.",
        "pt-BR": "Tudo permanece no seu Mac.",
        "nl": "Alles blijft op je Mac.",
        "ja": "すべてMac内に保存されます。",
        "zh-Hans": "所有数据都保留在你的 Mac 上。",
        "ko": "모든 데이터는 Mac에만 저장됩니다.",
        "ru": "Все данные остаются на вашем Mac.",
    },
    "onb.start": {
        "en": "Start", "fr": "Commencer", "es": "Comenzar", "de": "Starten",
        "it": "Inizia", "pt-BR": "Começar", "nl": "Starten", "ja": "開始",
        "zh-Hans": "开始", "ko": "시작", "ru": "Начать",
    },
    "onb.cam.denied.full": {
        "en": "Camera access denied. Enable it in System Settings › Privacy › Camera.",
        "fr": "Accès caméra refusé. Active-le dans Réglages Système › Confidentialité › Caméra.",
        "es": "Acceso a la cámara denegado. Actívalo en Ajustes del Sistema › Privacidad › Cámara.",
        "de": "Kamerazugriff verweigert. Aktiviere ihn in Systemeinstellungen › Datenschutz › Kamera.",
        "it": "Accesso alla fotocamera negato. Attivalo in Impostazioni di Sistema › Privacy › Fotocamera.",
        "pt-BR": "Acesso à câmera negado. Ative em Ajustes do Sistema › Privacidade › Câmera.",
        "nl": "Cameratoegang geweigerd. Schakel het in bij Systeeminstellingen › Privacy › Camera.",
        "ja": "カメラへのアクセスが拒否されました。システム設定 › プライバシー › カメラで許可してください。",
        "zh-Hans": "相机访问被拒绝。请在系统设置 › 隐私 › 相机中启用。",
        "ko": "카메라 접근이 거부되었습니다. 시스템 설정 › 개인정보 보호 › 카메라에서 허용하세요.",
        "ru": "Доступ к камере запрещён. Включите его в Настройках системы › Конфиденциальность › Камера.",
    },
    "onb.cam.denied": {
        "en": "Camera access denied.", "fr": "Accès caméra refusé.",
        "es": "Acceso a la cámara denegado.", "de": "Kamerazugriff verweigert.",
        "it": "Accesso alla fotocamera negato.", "pt-BR": "Acesso à câmera negado.",
        "nl": "Cameratoegang geweigerd.", "ja": "カメラへのアクセスが拒否されました。",
        "zh-Hans": "相机访问被拒绝。", "ko": "카메라 접근이 거부되었습니다.",
        "ru": "Доступ к камере запрещён.",
    },
    "onb.interrupted": {
        "en": "Enrollment interrupted.", "fr": "Enrôlement interrompu.",
        "es": "Registro interrumpido.", "de": "Erfassung abgebrochen.",
        "it": "Registrazione interrotta.", "pt-BR": "Registro interrompido.",
        "nl": "Registratie onderbroken.", "ja": "登録が中断されました。",
        "zh-Hans": "录入被中断。", "ko": "등록이 중단되었습니다.",
        "ru": "Регистрация прервана.",
    },
    "onb.scanning": {
        "en": "Analyzing your face…", "fr": "Analyse de ton visage…",
        "es": "Analizando tu rostro…", "de": "Gesicht wird analysiert…",
        "it": "Analisi del volto…", "pt-BR": "Analisando seu rosto…",
        "nl": "Je gezicht analyseren…", "ja": "顔を解析中…",
        "zh-Hans": "正在分析你的面容…", "ko": "얼굴 분석 중…",
        "ru": "Анализ вашего лица…",
    },
    "onb.captures": {
        "en": "%d / %d captures", "fr": "%d / %d captures",
        "es": "%d / %d capturas", "de": "%d / %d Aufnahmen",
        "it": "%d / %d acquisizioni", "pt-BR": "%d / %d capturas",
        "nl": "%d / %d opnames", "ja": "%d / %d 枚",
        "zh-Hans": "%d / %d 张", "ko": "%d / %d 회", "ru": "%d / %d снимков",
    },
    "onb.look": {
        "en": "Look at the camera and move your head gently.",
        "fr": "Regarde la caméra et bouge doucement la tête.",
        "es": "Mira a la cámara y mueve la cabeza suavemente.",
        "de": "Schau in die Kamera und bewege den Kopf sanft.",
        "it": "Guarda la fotocamera e muovi lentamente la testa.",
        "pt-BR": "Olhe para a câmera e mova a cabeça suavemente.",
        "nl": "Kijk in de camera en beweeg je hoofd rustig.",
        "ja": "カメラを見て、ゆっくり頭を動かしてください。",
        "zh-Hans": "看着摄像头，缓缓转动头部。",
        "ko": "카메라를 보며 머리를 천천히 움직이세요.",
        "ru": "Смотрите в камеру и плавно двигайте головой.",
    },
    "onb.done.title": {
        "en": "Face Registered", "fr": "Visage enregistré",
        "es": "Rostro registrado", "de": "Gesicht erfasst",
        "it": "Volto registrato", "pt-BR": "Rosto registrado",
        "nl": "Gezicht vastgelegd", "ja": "顔を登録しました",
        "zh-Hans": "面容已录入", "ko": "얼굴 등록 완료", "ru": "Лицо зарегистрировано",
    },
    "onb.done.body": {
        "en": "You can now enable Face ID for sudo in Settings.",
        "fr": "Tu peux maintenant activer Face ID pour sudo dans les réglages.",
        "es": "Ya puedes activar Face ID para sudo en los ajustes.",
        "de": "Du kannst Face ID für sudo jetzt in den Einstellungen aktivieren.",
        "it": "Ora puoi attivare Face ID per sudo nelle impostazioni.",
        "pt-BR": "Agora você pode ativar o Face ID para sudo nos ajustes.",
        "nl": "Je kunt Face ID voor sudo nu inschakelen in de instellingen.",
        "ja": "設定でsudo用のFace IDを有効にできます。",
        "zh-Hans": "现在可以在设置中为 sudo 启用 Face ID。",
        "ko": "이제 설정에서 sudo용 Face ID를 켤 수 있습니다.",
        "ru": "Теперь вы можете включить Face ID для sudo в настройках.",
    },
    "onb.done.btn": {
        "en": "Done", "fr": "Terminé", "es": "Listo", "de": "Fertig",
        "it": "Fine", "pt-BR": "Concluir", "nl": "Klaar", "ja": "完了",
        "zh-Hans": "完成", "ko": "완료", "ru": "Готово",
    },
    "onb.fail.title": {
        "en": "Enrollment Failed", "fr": "Échec de l'enrôlement",
        "es": "Error en el registro", "de": "Erfassung fehlgeschlagen",
        "it": "Registrazione non riuscita", "pt-BR": "Falha no registro",
        "nl": "Registratie mislukt", "ja": "登録に失敗しました",
        "zh-Hans": "录入失败", "ko": "등록 실패", "ru": "Не удалось зарегистрировать",
    },
    "onb.close": {
        "en": "Close", "fr": "Fermer", "es": "Cerrar", "de": "Schließen",
        "it": "Chiudi", "pt-BR": "Fechar", "nl": "Sluiten", "ja": "閉じる",
        "zh-Hans": "关闭", "ko": "닫기", "ru": "Закрыть",
    },
    "onb.retry": {
        "en": "Retry", "fr": "Réessayer", "es": "Reintentar",
        "de": "Wiederholen", "it": "Riprova", "pt-BR": "Tentar de novo",
        "nl": "Opnieuw", "ja": "再試行", "zh-Hans": "重试", "ko": "다시 시도",
        "ru": "Повторить",
    },
    "set.title": {
        "en": "Mugshot Settings", "fr": "Réglages Mugshot", "es": "Ajustes de Mugshot",
        "de": "Mugshot-Einstellungen", "it": "Impostazioni Mugshot",
        "pt-BR": "Ajustes do Mugshot", "nl": "Mugshot-instellingen",
        "ja": "Mugshot設定", "zh-Hans": "Mugshot 设置", "ko": "Mugshot 설정",
        "ru": "Настройки Mugshot",
    },
    "set.section.face": {
        "en": "Your Face", "fr": "Ton visage", "es": "Tu rostro",
        "de": "Dein Gesicht", "it": "Il tuo volto", "pt-BR": "Seu rosto",
        "nl": "Je gezicht", "ja": "あなたの顔", "zh-Hans": "你的面容",
        "ko": "내 얼굴", "ru": "Ваше лицо",
    },
    "set.face.yes": {
        "en": "Face registered", "fr": "Visage enregistré", "es": "Rostro registrado",
        "de": "Gesicht erfasst", "it": "Volto registrato", "pt-BR": "Rosto registrado",
        "nl": "Gezicht vastgelegd", "ja": "顔が登録済み", "zh-Hans": "面容已录入",
        "ko": "얼굴 등록됨", "ru": "Лицо зарегистрировано",
    },
    "set.face.no": {
        "en": "No face registered", "fr": "Aucun visage enregistré",
        "es": "Ningún rostro registrado", "de": "Kein Gesicht erfasst",
        "it": "Nessun volto registrato", "pt-BR": "Nenhum rosto registrado",
        "nl": "Geen gezicht vastgelegd", "ja": "顔が未登録",
        "zh-Hans": "尚未录入面容", "ko": "등록된 얼굴 없음",
        "ru": "Лицо не зарегистрировано",
    },
    "set.face.reenroll": {
        "en": "Re-enroll…", "fr": "Ré-enrôler…", "es": "Volver a registrar…",
        "de": "Neu erfassen…", "it": "Registra di nuovo…",
        "pt-BR": "Registrar de novo…", "nl": "Opnieuw vastleggen…",
        "ja": "再登録…", "zh-Hans": "重新录入…", "ko": "다시 등록…",
        "ru": "Заново…",
    },
    "set.face.setup": {
        "en": "Set Up…", "fr": "Configurer…", "es": "Configurar…",
        "de": "Einrichten…", "it": "Configura…", "pt-BR": "Configurar…",
        "nl": "Instellen…", "ja": "設定…", "zh-Hans": "设置…", "ko": "설정…",
        "ru": "Настроить…",
    },
    "set.section.sudo": {
        "en": "Terminal (sudo)", "fr": "Terminal (sudo)", "es": "Terminal (sudo)",
        "de": "Terminal (sudo)", "it": "Terminale (sudo)", "pt-BR": "Terminal (sudo)",
        "nl": "Terminal (sudo)", "ja": "ターミナル (sudo)", "zh-Hans": "终端 (sudo)",
        "ko": "터미널 (sudo)", "ru": "Терминал (sudo)",
    },
    "set.sudo.toggle": {
        "en": "Enable Face ID for sudo", "fr": "Activer Face ID pour sudo",
        "es": "Activar Face ID para sudo", "de": "Face ID für sudo aktivieren",
        "it": "Attiva Face ID per sudo", "pt-BR": "Ativar Face ID para sudo",
        "nl": "Face ID inschakelen voor sudo", "ja": "sudo用のFace IDを有効にする",
        "zh-Hans": "为 sudo 启用 Face ID", "ko": "sudo용 Face ID 켜기",
        "ru": "Включить Face ID для sudo",
    },
    # Décrivait « Demande ton mot de passe admin », ce qui n'est plus vrai : le parcours
    # passe par deux autorisations macOS, pas par une invite de mot de passe.
    "set.sudo.desc": {
        "en": "Your password always stays as a fallback.",
        "fr": "Votre mot de passe reste toujours en repli.",
        "es": "Tu contraseña siempre queda como alternativa.",
        "de": "Dein Passwort bleibt immer als Rückfallebene.",
        "it": "La tua password resta sempre come ripiego.",
        "pt-BR": "Sua senha continua sempre como alternativa.",
        "nl": "Je wachtwoord blijft altijd als terugval.",
        "ja": "パスワードは常に代替手段として残ります。",
        "zh-Hans": "你的密码始终作为后备保留。",
        "ko": "암호는 항상 대체 수단으로 남습니다.",
        "ru": "Ваш пароль всегда остаётся запасным вариантом.",
    },
    "set.section.behavior": {
        "en": "Behavior", "fr": "Comportement", "es": "Comportamiento",
        "de": "Verhalten", "it": "Comportamento", "pt-BR": "Comportamento",
        "nl": "Gedrag", "ja": "動作", "zh-Hans": "行为", "ko": "동작",
        "ru": "Поведение",
    },
    "set.behavior.modal": {
        "en": "Choice panel (Face ID / Fingerprint)",
        "fr": "Panneau de choix (Face ID / Empreinte)",
        "es": "Panel de elección (Face ID / Huella)",
        "de": "Auswahlfenster (Face ID / Fingerabdruck)",
        "it": "Pannello di scelta (Face ID / Impronta)",
        "pt-BR": "Painel de escolha (Face ID / Digital)",
        "nl": "Keuzevenster (Face ID / Vingerafdruk)",
        "ja": "選択パネル (Face ID / 指紋)",
        "zh-Hans": "选择面板 (Face ID / 指纹)",
        "ko": "선택 패널 (Face ID / 지문)",
        "ru": "Панель выбора (Face ID / отпечаток)",
    },
    "set.behavior.hud": {
        "en": "Animated capsule (Dynamic Island)",
        "fr": "Capsule animée (Dynamic Island)",
        "es": "Cápsula animada (Dynamic Island)",
        "de": "Animierte Kapsel (Dynamic Island)",
        "it": "Capsula animata (Dynamic Island)",
        "pt-BR": "Cápsula animada (Dynamic Island)",
        "nl": "Geanimeerde capsule (Dynamic Island)",
        "ja": "アニメーションカプセル (Dynamic Island)",
        "zh-Hans": "动画胶囊 (灵动岛)",
        "ko": "애니메이션 캡슐 (다이나믹 아일랜드)",
        "ru": "Анимированная капсула (Dynamic Island)",
    },
    "set.behavior.camera": {
        "en": "Camera", "fr": "Caméra", "es": "Cámara", "de": "Kamera",
        "it": "Fotocamera", "pt-BR": "Câmera", "nl": "Camera", "ja": "カメラ",
        "zh-Hans": "摄像头", "ko": "카메라", "ru": "Камера",
    },
    "set.behavior.camera.auto": {
        "en": "Automatic", "fr": "Automatique", "es": "Automática", "de": "Automatisch",
        "it": "Automatica", "pt-BR": "Automática", "nl": "Automatisch", "ja": "自動",
        "zh-Hans": "自动", "ko": "자동", "ru": "Автоматически",
    },
    "set.behavior.camera.iphone": {
        "en": "%@ (iPhone)", "fr": "%@ (iPhone)", "es": "%@ (iPhone)", "de": "%@ (iPhone)",
        "it": "%@ (iPhone)", "pt-BR": "%@ (iPhone)", "nl": "%@ (iPhone)", "ja": "%@（iPhone）",
        "zh-Hans": "%@（iPhone）", "ko": "%@(iPhone)", "ru": "%@ (iPhone)",
    },
    "set.behavior.camera.desc": {
        "en": "Automatic prefers the built-in camera over a paired iPhone.",
        "fr": "En automatique, la caméra intégrée est préférée à un iPhone appairé.",
        "es": "El modo automático prefiere la cámara integrada a un iPhone emparejado.",
        "de": "Automatisch bevorzugt die eingebaute Kamera gegenüber einem gekoppelten iPhone.",
        "it": "La modalità automatica preferisce la fotocamera integrata a un iPhone abbinato.",
        "pt-BR": "O modo automático prefere a câmera integrada a um iPhone pareado.",
        "nl": "Automatisch geeft voorrang aan de ingebouwde camera boven een gekoppelde iPhone.",
        "ja": "自動では、ペアリング済みiPhoneより内蔵カメラを優先します。",
        "zh-Hans": "自动模式优先使用内置摄像头，而非已配对的 iPhone。",
        "ko": "자동은 페어링된 iPhone보다 내장 카메라를 우선합니다.",
        "ru": "В автоматическом режиме встроенная камера предпочтительнее сопряжённого iPhone.",
    },
    "set.behavior.sensitivity": {
        "en": "Sensitivity", "fr": "Sensibilité", "es": "Sensibilidad",
        "de": "Empfindlichkeit", "it": "Sensibilità", "pt-BR": "Sensibilidade",
        "nl": "Gevoeligheid", "ja": "感度", "zh-Hans": "灵敏度",
        "ko": "민감도", "ru": "Чувствительность",
    },
    "set.behavior.sensitivity.desc": {
        "en": "Higher = stricter (fewer false positives).",
        "fr": "Plus haut = plus strict (moins de faux positifs).",
        "es": "Más alto = más estricto (menos falsos positivos).",
        "de": "Höher = strenger (weniger Fehlerkennungen).",
        "it": "Più alto = più severo (meno falsi positivi).",
        "pt-BR": "Mais alto = mais rígido (menos falsos positivos).",
        "nl": "Hoger = strenger (minder valse positieven).",
        "ja": "高いほど厳格 (誤認識が減少)。",
        "zh-Hans": "越高越严格（误识别更少）。",
        "ko": "높을수록 엄격함 (오인식 감소).",
        "ru": "Выше = строже (меньше ложных срабатываний).",
    },
    # Distinct de "set.behavior.camera" (l'étiquette du menu déroulant) : les deux clés
    # portaient le même nom, et celle-ci écrasait l'autre — le sélecteur de caméra
    # s'intitulait donc « Réglages caméra système… ».
    "set.behavior.camera.system": {
        "en": "System camera settings…", "fr": "Réglages caméra système…",
        "es": "Ajustes de cámara del sistema…", "de": "System-Kameraeinstellungen…",
        "it": "Impostazioni fotocamera di sistema…",
        "pt-BR": "Ajustes de câmera do sistema…",
        "nl": "Systeemcamera-instellingen…", "ja": "システムのカメラ設定…",
        "zh-Hans": "系统相机设置…", "ko": "시스템 카메라 설정…",
        "ru": "Системные настройки камеры…",
    },
    "set.msg.buildfail": {
        "en": "Module build failed: %@", "fr": "Échec de compilation du module : %@",
        "es": "Error al compilar el módulo: %@", "de": "Modul-Build fehlgeschlagen: %@",
        "it": "Compilazione del modulo non riuscita: %@",
        "pt-BR": "Falha ao compilar o módulo: %@",
        "nl": "Module bouwen mislukt: %@", "ja": "モジュールのビルドに失敗: %@",
        "zh-Hans": "模块编译失败：%@", "ko": "모듈 빌드 실패: %@",
        "ru": "Не удалось собрать модуль: %@",
    },
    "set.msg.sudo.on": {
        "en": "Face ID enabled for sudo.", "fr": "Face ID activé pour sudo.",
        "es": "Face ID activado para sudo.", "de": "Face ID für sudo aktiviert.",
        "it": "Face ID attivato per sudo.", "pt-BR": "Face ID ativado para sudo.",
        "nl": "Face ID ingeschakeld voor sudo.", "ja": "sudo用のFace IDを有効にしました。",
        "zh-Hans": "已为 sudo 启用 Face ID。", "ko": "sudo용 Face ID를 켰습니다.",
        "ru": "Face ID включён для sudo.",
    },
    "set.msg.sudo.off": {
        "en": "Face ID disabled for sudo.", "fr": "Face ID désactivé pour sudo.",
        "es": "Face ID desactivado para sudo.", "de": "Face ID für sudo deaktiviert.",
        "it": "Face ID disattivato per sudo.", "pt-BR": "Face ID desativado para sudo.",
        "nl": "Face ID uitgeschakeld voor sudo.", "ja": "sudo用のFace IDを無効にしました。",
        "zh-Hans": "已为 sudo 停用 Face ID。", "ko": "sudo용 Face ID를 껐습니다.",
        "ru": "Face ID отключён для sudo.",
    },
    "set.msg.cancelled": {
        "en": "Cancelled: %@", "fr": "Annulé : %@", "es": "Cancelado: %@",
        "de": "Abgebrochen: %@", "it": "Annullato: %@", "pt-BR": "Cancelado: %@",
        "nl": "Geannuleerd: %@", "ja": "キャンセルされました: %@",
        "zh-Hans": "已取消：%@", "ko": "취소됨: %@", "ru": "Отменено: %@",
    },
    "move.title": {
        "en": "Move Mugshot to your Applications folder",
        "fr": "Déplace Mugshot dans ton dossier Applications",
    },
    "move.body.dmg": {
        "en": "Mugshot is running from the disk image. Face ID for sudo needs a privileged "
              "helper, and that helper cannot survive the image being ejected.\n\n"
              "Drag Mugshot onto the Applications folder in the disk image window, then "
              "open it from there.",
        "fr": "Mugshot s'exécute depuis l'image disque. Face ID pour sudo repose sur un "
              "assistant privilégié, qui ne peut pas survivre à l'éjection de l'image.\n\n"
              "Glisse Mugshot sur le dossier Applications dans la fenêtre de l'image "
              "disque, puis ouvre-le depuis là.",
    },
    "move.body.other": {
        "en": "Mugshot is running from outside the Applications folder. Face ID for sudo "
              "needs a privileged helper registered from a stable location, so moving or "
              "deleting the app later silently breaks it.\n\n"
              "Move Mugshot to Applications and open it from there.",
        "fr": "Mugshot s'exécute hors du dossier Applications. Face ID pour sudo repose "
              "sur un assistant privilégié enregistré depuis un emplacement stable : "
              "déplacer ou supprimer l'app ensuite le casse silencieusement.\n\n"
              "Déplace Mugshot dans Applications et ouvre-le depuis là.",
    },
    "move.reveal": {
        "en": "Show me", "fr": "Montre-moi",
    },
    "move.ignore": {
        "en": "Continue anyway", "fr": "Continuer quand même",
    },
    "fda.needed": {
        "en": "Full Disk Access needed (see the window).",
        "fr": "Accès complet au disque requis (voir la fenêtre).",
    },
    "fda.title": {
        "en": "Full Disk Access required",
        "fr": "Accès complet au disque requis",
    },
    "fda.body": {
        "en": "On macOS 26, enabling Face ID for sudo needs Full Disk Access for "
              "Mugshot's helper.\n\n1. Click Open Settings below.\n2. In the list, "
              "turn on “MugshotHelper” (or add it with +, path below):\n%@\n\n"
              "3. Come back here and toggle it on again.",
        "fr": "Sur macOS 26, activer Face ID pour sudo nécessite l'Accès complet au "
              "disque pour l'assistant de Mugshot.\n\n1. Clique « Ouvrir les Réglages » "
              "ci-dessous.\n2. Dans la liste, active « MugshotHelper » (ou ajoute-le "
              "avec +, chemin ci-dessous) :\n%@\n\n3. Reviens ici et réactive le toggle.",
    },
    "fda.open": {
        "en": "Open Settings", "fr": "Ouvrir les Réglages",
    },
    "fda.cancel": {
        "en": "Later", "fr": "Plus tard",
    },
    # ---- désinstallation ----
    "uninstall.action": {
        "en": "Uninstall Mugshot…", "fr": "Désinstaller Mugshot…",
        "es": "Desinstalar Mugshot…", "de": "Mugshot deinstallieren…",
        "it": "Disinstalla Mugshot…", "pt-BR": "Desinstalar o Mugshot…",
        "nl": "Mugshot verwijderen…", "ja": "Mugshotをアンインストール…",
        "zh-Hans": "卸载 Mugshot…", "ko": "Mugshot 제거…",
        "ru": "Удалить Mugshot…",
    },
    "uninstall.confirm.title": {
        "en": "Uninstall Mugshot?", "fr": "Désinstaller Mugshot ?",
        "es": "¿Desinstalar Mugshot?", "de": "Mugshot deinstallieren?",
        "it": "Disinstallare Mugshot?", "pt-BR": "Desinstalar o Mugshot?",
        "nl": "Mugshot verwijderen?", "ja": "Mugshotをアンインストールしますか？",
        "zh-Hans": "要卸载 Mugshot 吗？", "ko": "Mugshot을 제거할까요?",
        "ru": "Удалить Mugshot?",
    },
    "uninstall.confirm.body": {
        "en": "This removes the sudo rule and the PAM module, restores the system Touch "
              "ID rule, and unregisters the helper and the login item.\n\n"
              "Dragging the app to the Trash on its own would leave all of that behind — "
              "including system Touch ID for sudo, which would stay switched off.",
        "fr": "Ceci retire la règle sudo et le module PAM, rétablit la règle Touch ID "
              "système, et désenregistre l'assistant et l'ouverture à la session.\n\n"
              "Mettre simplement l'app à la corbeille laisserait tout cela en place — "
              "y compris Touch ID système pour sudo, qui resterait désactivé.",
        "es": "Esto elimina la regla de sudo y el módulo PAM, restaura la regla de Touch "
              "ID del sistema y da de baja el asistente y el ítem de inicio.\n\n"
              "Arrastrar la app a la Papelera dejaría todo eso — incluido Touch ID del "
              "sistema para sudo, que seguiría desactivado.",
        "de": "Das entfernt die sudo-Regel und das PAM-Modul, stellt die System-Touch-ID-"
              "Regel wieder her und meldet Helfer und Anmeldeobjekt ab.\n\n"
              "Die App nur in den Papierkorb zu ziehen würde all das zurücklassen — "
              "einschließlich System-Touch-ID für sudo, das ausgeschaltet bliebe.",
        "it": "Rimuove la regola sudo e il modulo PAM, ripristina la regola Touch ID di "
              "sistema e annulla la registrazione dell'assistente e dell'elemento login."
              "\n\nTrascinare l'app nel Cestino lascerebbe tutto questo — compreso Touch "
              "ID di sistema per sudo, che resterebbe disattivato.",
        "pt-BR": "Isso remove a regra do sudo e o módulo PAM, restaura a regra do Touch ID "
                 "do sistema e cancela o registro do auxiliar e do item de início.\n\n"
                 "Arrastar o app para o Lixo deixaria tudo isso — inclusive o Touch ID do "
                 "sistema para sudo, que continuaria desligado.",
        "nl": "Dit verwijdert de sudo-regel en de PAM-module, herstelt de Touch ID-regel "
              "van het systeem en meldt de helper en het inlogitem af.\n\n"
              "De app alleen naar de prullenmand slepen zou dat allemaal achterlaten — "
              "inclusief Touch ID van het systeem voor sudo, dat uit zou blijven.",
        "ja": "sudoのルールとPAMモジュールを削除し、システムのTouch IDルールを復元して、"
              "ヘルパーとログイン項目の登録を解除します。\n\nAppをゴミ箱に入れるだけでは"
              "これらが残ります。sudo用のシステムTouch IDも無効のままになります。",
        "zh-Hans": "这会移除 sudo 规则和 PAM 模块，恢复系统 Touch ID 规则，并注销辅助程序与登录项。"
                   "\n\n仅把 App 拖到废纸篓会留下这一切——包括用于 sudo 的系统 Touch ID，它会一直处于关闭状态。",
        "ko": "sudo 규칙과 PAM 모듈을 제거하고, 시스템 Touch ID 규칙을 복원하며, 도우미와 "
              "로그인 항목의 등록을 해제합니다.\n\nApp을 휴지통으로 옮기기만 하면 이 모든 것이 "
              "남습니다. sudo용 시스템 Touch ID도 꺼진 채로 유지됩니다.",
        "ru": "Будут удалены правило sudo и модуль PAM, восстановлено системное правило "
              "Touch ID, а помощник и объект входа — отменены.\n\nПросто перетащить "
              "приложение в Корзину означало бы оставить всё это, включая системный "
              "Touch ID для sudo, который остался бы отключённым.",
    },
    "uninstall.confirm.data": {
        "en": "Also delete my enrolled face",
        "fr": "Effacer aussi mon visage enregistré",
        "es": "Eliminar también mi rostro registrado",
        "de": "Auch mein erfasstes Gesicht löschen",
        "it": "Elimina anche il mio volto registrato",
        "pt-BR": "Também apagar meu rosto registrado",
        "nl": "Verwijder ook mijn vastgelegde gezicht",
        "ja": "登録した顔も削除する",
        "zh-Hans": "同时删除已录入的面容",
        "ko": "등록한 얼굴도 삭제",
        "ru": "Также удалить зарегистрированное лицо",
    },
    "uninstall.confirm.ok": {
        "en": "Uninstall", "fr": "Désinstaller", "es": "Desinstalar",
        "de": "Deinstallieren", "it": "Disinstalla", "pt-BR": "Desinstalar",
        "nl": "Verwijderen", "ja": "アンインストール", "zh-Hans": "卸载",
        "ko": "제거", "ru": "Удалить",
    },
    "uninstall.running": {
        "en": "Uninstalling…", "fr": "Désinstallation en cours…",
        "es": "Desinstalando…", "de": "Wird deinstalliert…",
        "it": "Disinstallazione…", "pt-BR": "Desinstalando…",
        "nl": "Bezig met verwijderen…", "ja": "アンインストール中…",
        "zh-Hans": "正在卸载…", "ko": "제거 중…", "ru": "Удаление…",
    },
    "uninstall.failed": {
        "en": "Could not remove the sudo rule, so nothing was deleted: %@",
        "fr": "Impossible de retirer la règle sudo : rien n'a été supprimé (%@)",
        "es": "No se pudo quitar la regla de sudo, así que no se eliminó nada: %@",
        "de": "Die sudo-Regel ließ sich nicht entfernen, daher wurde nichts gelöscht: %@",
        "it": "Impossibile rimuovere la regola sudo, quindi non è stato eliminato nulla: %@",
        "pt-BR": "Não foi possível remover a regra do sudo, então nada foi excluído: %@",
        "nl": "De sudo-regel kon niet worden verwijderd, dus er is niets gewist: %@",
        "ja": "sudoのルールを削除できなかったため、何も削除していません: %@",
        "zh-Hans": "无法移除 sudo 规则，因此未删除任何内容：%@",
        "ko": "sudo 규칙을 제거하지 못해 아무것도 삭제하지 않았습니다: %@",
        "ru": "Не удалось удалить правило sudo, поэтому ничего не удалено: %@",
    },
    "uninstall.needs.helper": {
        "en": "Mugshot's helper must be approved before the sudo rule can be removed. "
              "macOS just opened Login Items — turn Mugshot on there, then try again.",
        "fr": "L'assistant de Mugshot doit être autorisé avant de pouvoir retirer la règle "
              "sudo. macOS vient d'ouvrir les Éléments d'ouverture — activez-y Mugshot, "
              "puis réessayez.",
        "es": "El asistente de Mugshot debe autorizarse antes de quitar la regla de sudo. "
              "macOS abrió los Ítems de inicio: activa Mugshot ahí y vuelve a intentarlo.",
        "de": "Mugshots Helfer muss freigegeben werden, bevor die sudo-Regel entfernt "
              "werden kann. macOS hat die Anmeldeobjekte geöffnet — aktiviere Mugshot "
              "dort und versuche es erneut.",
        "it": "L'assistente di Mugshot va autorizzato prima di rimuovere la regola sudo. "
              "macOS ha aperto gli Elementi login: attiva Mugshot e riprova.",
        "pt-BR": "O auxiliar do Mugshot precisa ser autorizado antes de remover a regra do "
                 "sudo. O macOS abriu os Itens de início: ative o Mugshot e tente de novo.",
        "nl": "De helper van Mugshot moet worden goedgekeurd voordat de sudo-regel kan "
              "worden verwijderd. macOS opende Inlogitems — schakel Mugshot daar in en "
              "probeer opnieuw.",
        "ja": "sudoルールを削除するには、Mugshotのヘルパーを許可する必要があります。"
              "macOSがログイン項目を開いたので、Mugshotをオンにしてから再試行してください。",
        "zh-Hans": "移除 sudo 规则前需要先允许 Mugshot 的辅助程序。macOS 已打开登录项——"
                   "在那里开启 Mugshot，然后重试。",
        "ko": "sudo 규칙을 제거하려면 먼저 Mugshot 도우미를 허용해야 합니다. macOS가 "
              "로그인 항목을 열었습니다. 거기서 Mugshot을 켠 뒤 다시 시도하세요.",
        "ru": "Помощник Mugshot должен быть разрешён, прежде чем можно удалить правило "
              "sudo. macOS открыл Объекты входа — включите там Mugshot и повторите.",
    },
    "uninstall.failed.title": {
        "en": "Could not remove the sudo rule", "fr": "Impossible de retirer la règle sudo",
        "es": "No se pudo quitar la regla de sudo", "de": "sudo-Regel ließ sich nicht entfernen",
        "it": "Impossibile rimuovere la regola sudo", "pt-BR": "Não foi possível remover a regra do sudo",
        "nl": "Kon de sudo-regel niet verwijderen", "ja": "sudoルールを削除できませんでした",
        "zh-Hans": "无法移除 sudo 规则", "ko": "sudo 규칙을 제거할 수 없습니다",
        "ru": "Не удалось удалить правило sudo",
    },
    "uninstall.failed.manual": {
        "en": "Nothing was deleted. You can remove the rule yourself from a terminal — "
              "the command is on your clipboard if you choose Copy.",
        "fr": "Rien n'a été supprimé. Vous pouvez retirer la règle vous-même depuis un "
              "terminal — la commande est copiée si vous choisissez Copier.",
        "es": "No se eliminó nada. Puedes quitar la regla desde un terminal: el comando se "
              "copia si eliges Copiar.",
        "de": "Es wurde nichts gelöscht. Du kannst die Regel selbst im Terminal entfernen — "
              "der Befehl liegt in der Zwischenablage, wenn du Kopieren wählst.",
        "it": "Non è stato eliminato nulla. Puoi rimuovere la regola dal Terminale: il "
              "comando viene copiato se scegli Copia.",
        "pt-BR": "Nada foi excluído. Você pode remover a regra pelo Terminal — o comando é "
                 "copiado se escolher Copiar.",
        "nl": "Er is niets verwijderd. Je kunt de regel zelf via Terminal verwijderen — het "
              "commando staat op je klembord als je Kopiëren kiest.",
        "ja": "何も削除していません。ターミナルから自分で削除できます。「コピー」を選ぶと"
              "コマンドがクリップボードに入ります。",
        "zh-Hans": "未删除任何内容。你可以在终端里自行移除规则——选择“拷贝”即可获得命令。",
        "ko": "아무것도 삭제하지 않았습니다. 터미널에서 직접 규칙을 제거할 수 있습니다. "
              "‘복사’를 선택하면 명령이 클립보드에 담깁니다.",
        "ru": "Ничего не удалено. Правило можно убрать самостоятельно в Терминале — команда "
              "попадёт в буфер обмена, если выбрать «Скопировать».",
    },
    "uninstall.failed.copy": {
        "en": "Copy the command", "fr": "Copier la commande", "es": "Copiar el comando",
        "de": "Befehl kopieren", "it": "Copia il comando", "pt-BR": "Copiar o comando",
        "nl": "Commando kopiëren", "ja": "コマンドをコピー", "zh-Hans": "拷贝命令",
        "ko": "명령 복사", "ru": "Скопировать команду",
    },
    "uninstall.step.pam": {
        "en": "sudo rule removed, system Touch ID restored",
        "fr": "règle sudo retirée, Touch ID système rétabli",
        "es": "regla de sudo eliminada, Touch ID del sistema restaurado",
        "de": "sudo-Regel entfernt, System-Touch-ID wiederhergestellt",
        "it": "regola sudo rimossa, Touch ID di sistema ripristinato",
        "pt-BR": "regra do sudo removida, Touch ID do sistema restaurado",
        "nl": "sudo-regel verwijderd, Touch ID van systeem hersteld",
        "ja": "sudoルールを削除し、システムTouch IDを復元しました",
        "zh-Hans": "已移除 sudo 规则，已恢复系统 Touch ID",
        "ko": "sudo 규칙 제거, 시스템 Touch ID 복원",
        "ru": "правило sudo удалено, системный Touch ID восстановлен",
    },
    "uninstall.step.helper": {
        "en": "privileged helper unregistered",
        "fr": "assistant privilégié désenregistré",
        "es": "asistente con privilegios dado de baja",
        "de": "privilegierter Helfer abgemeldet",
        "it": "assistente privilegiato annullato",
        "pt-BR": "auxiliar privilegiado desregistrado",
        "nl": "bevoorrechte helper afgemeld",
        "ja": "特権ヘルパーの登録を解除しました",
        "zh-Hans": "已注销特权辅助程序",
        "ko": "권한 도우미 등록 해제됨",
        "ru": "привилегированный помощник отменён",
    },
    "uninstall.step.login": {
        "en": "removed from login items", "fr": "retiré de l'ouverture à la session",
        "es": "eliminado de los ítems de inicio", "de": "aus den Anmeldeobjekten entfernt",
        "it": "rimosso dagli elementi login", "pt-BR": "removido dos itens de início",
        "nl": "verwijderd uit inlogitems", "ja": "ログイン項目から削除しました",
        "zh-Hans": "已从登录项中移除", "ko": "로그인 항목에서 제거됨",
        "ru": "удалено из объектов входа",
    },
    "uninstall.step.data": {
        "en": "enrolled face deleted", "fr": "visage enregistré effacé",
        "es": "rostro registrado eliminado", "de": "erfasstes Gesicht gelöscht",
        "it": "volto registrato eliminato", "pt-BR": "rosto registrado apagado",
        "nl": "vastgelegd gezicht verwijderd", "ja": "登録した顔を削除しました",
        "zh-Hans": "已删除录入的面容", "ko": "등록한 얼굴 삭제됨",
        "ru": "зарегистрированное лицо удалено",
    },
    "uninstall.done.title": {
        "en": "Mugshot has been removed from your system",
        "fr": "Mugshot a été retiré de votre système",
        "es": "Mugshot se ha eliminado de tu sistema",
        "de": "Mugshot wurde von deinem System entfernt",
        "it": "Mugshot è stato rimosso dal sistema",
        "pt-BR": "O Mugshot foi removido do seu sistema",
        "nl": "Mugshot is van je systeem verwijderd",
        "ja": "Mugshotをシステムから削除しました",
        "zh-Hans": "Mugshot 已从系统中移除",
        "ko": "Mugshot을 시스템에서 제거했습니다",
        "ru": "Mugshot удалён из системы",
    },
    "uninstall.done.body": {
        "en": "All that is left is the app itself.",
        "fr": "Il ne reste que l'app elle-même.",
        "es": "Solo queda la propia app.",
        "de": "Übrig ist nur noch die App selbst.",
        "it": "Resta solo l'app.",
        "pt-BR": "Resta apenas o próprio app.",
        "nl": "Alleen de app zelf blijft over.",
        "ja": "残っているのはApp本体だけです。",
        "zh-Hans": "只剩下 App 本身。",
        "ko": "이제 App 자체만 남았습니다.",
        "ru": "Осталось только само приложение.",
    },
    "uninstall.done.trash": {
        "en": "Move to Trash and Quit", "fr": "Mettre à la corbeille et quitter",
        "es": "Mover a la Papelera y salir", "de": "In den Papierkorb legen und beenden",
        "it": "Sposta nel Cestino ed esci", "pt-BR": "Mover para o Lixo e sair",
        "nl": "Naar prullenmand en afsluiten", "ja": "ゴミ箱に入れて終了",
        "zh-Hans": "移到废纸篓并退出", "ko": "휴지통으로 옮기고 종료",
        "ru": "Переместить в Корзину и выйти",
    },

    # ---- mise en garde à la fermeture ----
    "quit.title": {
        "en": "Quitting turns off Face ID for sudo",
        "fr": "Quitter désactive Face ID pour sudo",
        "es": "Salir desactiva Face ID para sudo",
        "de": "Beenden schaltet Face ID für sudo ab",
        "it": "Uscire disattiva Face ID per sudo",
        "pt-BR": "Sair desativa o Face ID para o sudo",
        "nl": "Afsluiten schakelt Face ID voor sudo uit",
        "ja": "終了するとsudo用のFace IDが働かなくなります",
        "zh-Hans": "退出会关闭用于 sudo 的 Face ID",
        "ko": "종료하면 sudo용 Face ID가 꺼집니다",
        "ru": "Выход отключает Face ID для sudo",
    },
    "quit.body": {
        "en": "Mugshot runs the recognition itself, so sudo will ask for your password "
              "again until you reopen it.\n\nTo close the window without quitting, "
              "press ⌘W.",
        "fr": "Mugshot exécute lui-même la reconnaissance : sudo redemandera votre mot "
              "de passe tant que vous ne l'aurez pas rouvert.\n\nPour fermer la fenêtre "
              "sans quitter, appuyez sur ⌘W.",
        "es": "Mugshot ejecuta el reconocimiento, así que sudo volverá a pedir tu "
              "contraseña hasta que lo abras de nuevo.\n\nPara cerrar la ventana sin "
              "salir, pulsa ⌘W.",
        "de": "Mugshot führt die Erkennung selbst aus, daher fragt sudo wieder nach "
              "deinem Passwort, bis du es erneut öffnest.\n\nUm das Fenster zu "
              "schließen, ohne zu beenden, drücke ⌘W.",
        "it": "Mugshot esegue il riconoscimento, quindi sudo tornerà a chiedere la "
              "password finché non lo riapri.\n\nPer chiudere la finestra senza uscire, "
              "premi ⌘W.",
        "pt-BR": "O Mugshot faz o reconhecimento, então o sudo voltará a pedir sua senha "
                 "até você abri-lo de novo.\n\nPara fechar a janela sem sair, tecle ⌘W.",
        "nl": "Mugshot voert de herkenning zelf uit, dus sudo vraagt weer om je "
              "wachtwoord tot je het opnieuw opent.\n\nDruk op ⌘W om het venster te "
              "sluiten zonder af te sluiten.",
        "ja": "Mugshot自身が認証を行うため、再度開くまでsudoはパスワードを求めます。\n\n"
              "終了せずにウインドウを閉じるには ⌘W を押してください。",
        "zh-Hans": "识别由 Mugshot 自身执行，因此在你重新打开之前，sudo 会再次要求输入密码。"
                   "\n\n若只想关闭窗口而不退出，请按 ⌘W。",
        "ko": "인식은 Mugshot이 직접 수행하므로, 다시 열기 전까지 sudo가 암호를 요구합니다."
              "\n\n종료하지 않고 창만 닫으려면 ⌘W를 누르세요.",
        "ru": "Распознавание выполняет сам Mugshot, поэтому sudo снова будет запрашивать "
              "пароль, пока вы его не откроете.\n\nЧтобы закрыть окно, не выходя, "
              "нажмите ⌘W.",
    },
    "quit.confirm": {
        "en": "Quit anyway", "fr": "Quitter quand même", "es": "Salir de todos modos",
        "de": "Trotzdem beenden", "it": "Esci comunque", "pt-BR": "Sair mesmo assim",
        "nl": "Toch afsluiten", "ja": "それでも終了", "zh-Hans": "仍然退出",
        "ko": "그래도 종료", "ru": "Всё равно выйти",
    },
    "quit.cancel": {
        "en": "Keep running", "fr": "Laisser tourner", "es": "Dejar en marcha",
        "de": "Weiterlaufen lassen", "it": "Lascia in esecuzione", "pt-BR": "Manter em execução",
        "nl": "Laten draaien", "ja": "実行したままにする", "zh-Hans": "保持运行",
        "ko": "계속 실행", "ru": "Оставить работать",
    },

    # ---- déplacement vers Applications ----
    "move.doit": {
        "en": "Move to Applications", "fr": "Déplacer vers Applications",
        "es": "Mover a Aplicaciones", "de": "In „Programme“ bewegen",
        "it": "Sposta in Applicazioni", "pt-BR": "Mover para Aplicativos",
        "nl": "Naar Programma's verplaatsen", "ja": "「アプリケーション」に移動",
        "zh-Hans": "移到“应用程序”", "ko": "‘응용 프로그램’으로 이동",
        "ru": "Переместить в «Программы»",
    },
    "move.failed": {
        "en": "Could not move Mugshot to Applications",
        "fr": "Impossible de déplacer Mugshot vers Applications",
        "es": "No se pudo mover Mugshot a Aplicaciones",
        "de": "Mugshot konnte nicht nach „Programme“ bewegt werden",
        "it": "Impossibile spostare Mugshot in Applicazioni",
        "pt-BR": "Não foi possível mover o Mugshot para Aplicativos",
        "nl": "Kon Mugshot niet naar Programma's verplaatsen",
        "ja": "Mugshotを「アプリケーション」に移動できませんでした",
        "zh-Hans": "无法将 Mugshot 移到“应用程序”",
        "ko": "Mugshot을 ‘응용 프로그램’으로 이동할 수 없습니다",
        "ru": "Не удалось переместить Mugshot в «Программы»",
    },

    # ---- apparences multiples ----
    "set.face.append": {
        "en": "Add an appearance…", "fr": "Ajouter une apparence…",
        "es": "Añadir una apariencia…", "de": "Aussehen hinzufügen…",
        "it": "Aggiungi un aspetto…", "pt-BR": "Adicionar uma aparência…",
        "nl": "Uiterlijk toevoegen…", "ja": "容姿を追加…",
        "zh-Hans": "添加一种外观…", "ko": "다른 모습 추가…",
        "ru": "Добавить внешность…",
    },
    "set.face.append.desc": {
        "en": "glasses, a beard, evening light",
        "fr": "lunettes, barbe, lumière du soir",
        "es": "gafas, barba, luz de la tarde",
        "de": "Brille, Bart, Abendlicht",
        "it": "occhiali, barba, luce serale",
        "pt-BR": "óculos, barba, luz da noite",
        "nl": "bril, baard, avondlicht",
        "ja": "メガネ、ひげ、夕方の照明",
        "zh-Hans": "眼镜、胡子、傍晚光线",
        "ko": "안경, 수염, 저녁 조명",
        "ru": "очки, борода, вечерний свет",
    },
    "onb.title.append": {
        "en": "Add an Appearance", "fr": "Ajouter une apparence",
        "es": "Añadir una apariencia", "de": "Aussehen hinzufügen",
        "it": "Aggiungi un aspetto", "pt-BR": "Adicionar uma aparência",
        "nl": "Uiterlijk toevoegen", "ja": "容姿を追加",
        "zh-Hans": "添加一种外观", "ko": "다른 모습 추가",
        "ru": "Добавить внешность",
    },
    "onb.intro.append": {
        "en": "This adds to your enrolled face instead of replacing it. Useful with "
              "glasses on, a new beard, or in the light you usually work in.",
        "fr": "Ceci s'ajoute à votre visage enregistré au lieu de le remplacer. Utile "
              "avec des lunettes, une nouvelle barbe, ou dans la lumière où vous "
              "travaillez d'habitude.",
        "es": "Esto se añade a tu rostro registrado en lugar de reemplazarlo. Útil con "
              "gafas, una barba nueva o con la luz en la que sueles trabajar.",
        "de": "Das ergänzt dein erfasstes Gesicht, statt es zu ersetzen. Nützlich mit "
              "Brille, neuem Bart oder in deinem üblichen Arbeitslicht.",
        "it": "Si aggiunge al volto registrato invece di sostituirlo. Utile con gli "
              "occhiali, una barba nuova o con la luce in cui lavori di solito.",
        "pt-BR": "Isso soma ao rosto já registrado em vez de substituí-lo. Útil de óculos, "
                 "com barba nova ou na luz em que você costuma trabalhar.",
        "nl": "Dit komt bij je vastgelegde gezicht in plaats van het te vervangen. Handig "
              "met een bril, een nieuwe baard of in je gebruikelijke werklicht.",
        "ja": "登録済みの顔を置き換えるのではなく追加します。メガネをかけたとき、ひげを"
              "伸ばしたとき、いつも作業する照明のもとで役立ちます。",
        "zh-Hans": "这会在已录入的面容上追加，而不是替换。戴眼镜、留了胡子，或在你常用的光线下很有用。",
        "ko": "등록된 얼굴을 대체하지 않고 추가합니다. 안경을 썼을 때, 수염이 생겼을 때, "
              "평소 작업하는 조명에서 유용합니다.",
        "ru": "Это дополняет зарегистрированное лицо, а не заменяет его. Пригодится в "
              "очках, с новой бородой или при вашем обычном освещении.",
    },

    # ---- bandeau d'état de la fenêtre principale ----
    "banner.ready.title": {
        "en": "Ready", "fr": "Prêt", "es": "Listo", "de": "Bereit", "it": "Pronto",
        "pt-BR": "Pronto", "nl": "Klaar", "ja": "準備完了", "zh-Hans": "已就绪",
        "ko": "준비됨", "ru": "Готово",
    },
    "banner.ready.detail": {
        "en": "sudo unlocks with your face.",
        "fr": "sudo se déverrouille avec votre visage.",
        "es": "sudo se desbloquea con tu rostro.",
        "de": "sudo wird mit deinem Gesicht entsperrt.",
        "it": "sudo si sblocca con il tuo volto.",
        "pt-BR": "o sudo é desbloqueado com seu rosto.",
        "nl": "sudo wordt ontgrendeld met je gezicht.",
        "ja": "sudoが顔でロック解除されます。",
        "zh-Hans": "sudo 可用你的面容解锁。",
        "ko": "sudo가 얼굴로 잠금 해제됩니다.",
        "ru": "sudo разблокируется вашим лицом.",
    },
    "banner.ready.action": {
        "en": "Test", "fr": "Tester", "es": "Probar", "de": "Testen", "it": "Prova",
        "pt-BR": "Testar", "nl": "Testen", "ja": "テスト", "zh-Hans": "测试",
        "ko": "테스트", "ru": "Проверить",
    },
    "banner.noface.title": {
        "en": "No face registered yet", "fr": "Aucun visage enregistré",
        "es": "Aún no hay rostro registrado", "de": "Noch kein Gesicht erfasst",
        "it": "Nessun volto ancora registrato", "pt-BR": "Nenhum rosto registrado ainda",
        "nl": "Nog geen gezicht vastgelegd", "ja": "顔がまだ登録されていません",
        "zh-Hans": "尚未录入面容", "ko": "아직 등록된 얼굴이 없습니다",
        "ru": "Лицо ещё не зарегистрировано",
    },
    "banner.noface.detail": {
        "en": "Register your face to get started. It takes a few seconds.",
        "fr": "Enregistrez votre visage pour commencer. Ça prend quelques secondes.",
        "es": "Registra tu rostro para empezar. Solo toma unos segundos.",
        "de": "Erfasse dein Gesicht, um zu starten. Das dauert nur Sekunden.",
        "it": "Registra il tuo volto per iniziare. Bastano pochi secondi.",
        "pt-BR": "Registre seu rosto para começar. Leva alguns segundos.",
        "nl": "Leg je gezicht vast om te beginnen. Het duurt enkele seconden.",
        "ja": "まず顔を登録してください。数秒で完了します。",
        "zh-Hans": "先录入面容即可开始，只需几秒钟。",
        "ko": "얼굴을 등록해 시작하세요. 몇 초면 됩니다.",
        "ru": "Зарегистрируйте лицо, чтобы начать. Это займёт несколько секунд.",
    },
    "banner.nosudo.title": {
        "en": "Not enabled for sudo", "fr": "Pas encore activé pour sudo",
        "es": "Aún no activado para sudo", "de": "Für sudo noch nicht aktiviert",
        "it": "Non ancora attivo per sudo", "pt-BR": "Ainda não ativado para o sudo",
        "nl": "Nog niet ingeschakeld voor sudo", "ja": "sudo用に未設定です",
        "zh-Hans": "尚未为 sudo 启用", "ko": "sudo용으로 켜지지 않음",
        "ru": "Для sudo ещё не включено",
    },
    "banner.nosudo.detail": {
        "en": "macOS asks for two approvals. Mugshot walks you through them.",
        "fr": "macOS demande deux autorisations. Mugshot vous guide.",
        "es": "macOS pide dos permisos. Mugshot te guía.",
        "de": "macOS verlangt zwei Freigaben. Mugshot führt dich hindurch.",
        "it": "macOS chiede due autorizzazioni. Mugshot ti guida.",
        "pt-BR": "O macOS pede duas autorizações. O Mugshot conduz você.",
        "nl": "macOS vraagt twee goedkeuringen. Mugshot leidt je erdoorheen.",
        "ja": "macOSは2つの許可を求めます。Mugshotが順に案内します。",
        "zh-Hans": "macOS 需要两项授权，Mugshot 会逐步引导你。",
        "ko": "macOS는 두 가지 승인을 요구합니다. Mugshot이 안내합니다.",
        "ru": "macOS запросит два разрешения. Mugshot проведёт вас по ним.",
    },
    "banner.nosudo.action": {
        "en": "Enable", "fr": "Activer", "es": "Activar", "de": "Aktivieren",
        "it": "Attiva", "pt-BR": "Ativar", "nl": "Inschakelen", "ja": "有効にする",
        "zh-Hans": "启用", "ko": "켜기", "ru": "Включить",
    },

    # ---- feuille d'activation (les autorisations macOS) ----
    "setup.title": {
        "en": "Enable Face ID for sudo", "fr": "Activer Face ID pour sudo",
        "es": "Activar Face ID para sudo", "de": "Face ID für sudo aktivieren",
        "it": "Attiva Face ID per sudo", "pt-BR": "Ativar o Face ID para o sudo",
        "nl": "Face ID inschakelen voor sudo", "ja": "sudo用のFace IDを有効にする",
        "zh-Hans": "为 sudo 启用 Face ID", "ko": "sudo용 Face ID 켜기",
        "ru": "Включить Face ID для sudo",
    },
    "setup.intro": {
        "en": "macOS requires two approvals before Mugshot can touch the sudo "
              "configuration. Each step ticks itself off as soon as you grant it — "
              "you never have to start over.",
        "fr": "macOS exige deux autorisations avant que Mugshot puisse toucher à la "
              "configuration de sudo. Chaque étape se coche dès que vous l'accordez — "
              "vous n'avez jamais à recommencer.",
        "es": "macOS exige dos permisos antes de que Mugshot toque la configuración de "
              "sudo. Cada paso se marca en cuanto lo concedes: nunca hay que empezar de nuevo.",
        "de": "macOS verlangt zwei Freigaben, bevor Mugshot die sudo-Konfiguration ändern "
              "darf. Jeder Schritt hakt sich selbst ab — du musst nie von vorn beginnen.",
        "it": "macOS richiede due autorizzazioni prima che Mugshot possa toccare la "
              "configurazione di sudo. Ogni passaggio si spunta da solo: non si ricomincia mai.",
        "pt-BR": "O macOS exige duas autorizações antes que o Mugshot altere a configuração "
                 "do sudo. Cada etapa se marca sozinha — nunca é preciso recomeçar.",
        "nl": "macOS vereist twee goedkeuringen voordat Mugshot de sudo-configuratie mag "
              "aanpassen. Elke stap vinkt zichzelf af — je hoeft nooit opnieuw te beginnen.",
        "ja": "MugshotがsudoI設定に触れるには、macOSの許可が2つ必要です。許可すると各ステップは"
              "自動でチェックされ、やり直す必要はありません。",
        "zh-Hans": "在 Mugshot 修改 sudo 配置前，macOS 需要两项授权。每一步在你授权后会自动打勾，"
                   "无需从头再来。",
        "ko": "Mugshot이 sudo 설정을 변경하려면 macOS 승인 두 가지가 필요합니다. 각 단계는 "
              "허용하는 즉시 자동으로 완료되며, 다시 시작할 필요가 없습니다.",
        "ru": "macOS требует два разрешения, прежде чем Mugshot сможет менять настройку "
              "sudo. Каждый шаг отмечается сам — начинать заново не придётся.",
    },
    "setup.step.helper": {
        "en": "Allow Mugshot's helper", "fr": "Autoriser l'assistant de Mugshot",
        "es": "Permitir el asistente de Mugshot", "de": "Mugshots Helfer erlauben",
        "it": "Consenti l'assistente di Mugshot", "pt-BR": "Permitir o auxiliar do Mugshot",
        "nl": "Mugshots helper toestaan", "ja": "Mugshotのヘルパーを許可",
        "zh-Hans": "允许 Mugshot 的辅助程序", "ko": "Mugshot 도우미 허용",
        "ru": "Разрешить помощник Mugshot",
    },
    "setup.step.helper.detail": {
        "en": "In Settings › General › Login Items.",
        "fr": "Dans Réglages › Général › Ouverture et extensions.",
        "es": "En Ajustes › General › Ítems de inicio.",
        "de": "In Einstellungen › Allgemein › Anmeldeobjekte.",
        "it": "In Impostazioni › Generali › Elementi login.",
        "pt-BR": "Em Ajustes › Geral › Itens de início.",
        "nl": "In Instellingen › Algemeen › Inlogitems.",
        "ja": "設定 › 一般 › ログイン項目。",
        "zh-Hans": "在设置 › 通用 › 登录项。",
        "ko": "설정 › 일반 › 로그인 항목.",
        "ru": "В Настройках › Основные › Объекты входа.",
    },
    "setup.step.helper.waiting": {
        "en": "Waiting for you to turn it on in System Settings…",
        "fr": "En attente de son activation dans les Réglages Système…",
        "es": "Esperando a que lo actives en Ajustes del Sistema…",
        "de": "Warte darauf, dass du es in den Systemeinstellungen aktivierst…",
        "it": "In attesa che tu lo attivi in Impostazioni di Sistema…",
        "pt-BR": "Aguardando você ativar nos Ajustes do Sistema…",
        "nl": "Wachten tot je het inschakelt in Systeeminstellingen…",
        "ja": "システム設定でオンにするのを待っています…",
        "zh-Hans": "等待你在系统设置中开启…",
        "ko": "시스템 설정에서 켜기를 기다리는 중…",
        "ru": "Ожидание включения в Настройках системы…",
    },
    "setup.step.fda": {
        "en": "Grant Full Disk Access", "fr": "Accorder l'Accès complet au disque",
        "es": "Conceder Acceso completo al disco", "de": "Vollen Festplattenzugriff gewähren",
        "it": "Concedi Accesso completo al disco", "pt-BR": "Conceder Acesso total ao disco",
        "nl": "Volledige schijftoegang verlenen", "ja": "フルディスクアクセスを許可",
        "zh-Hans": "授予完全磁盘访问权限", "ko": "전체 디스크 접근 권한 허용",
        "ru": "Предоставить полный доступ к диску",
    },
    "setup.step.fda.detail": {
        "en": "macOS keeps the sudo configuration behind this permission.",
        "fr": "macOS place la configuration de sudo derrière cette autorisation.",
        "es": "macOS protege la configuración de sudo con este permiso.",
        "de": "macOS schützt die sudo-Konfiguration mit dieser Berechtigung.",
        "it": "macOS protegge la configurazione di sudo con questa autorizzazione.",
        "pt-BR": "O macOS protege a configuração do sudo com essa permissão.",
        "nl": "macOS beschermt de sudo-configuratie met deze toestemming.",
        "ja": "macOSはsudoの設定をこの権限で保護しています。",
        "zh-Hans": "macOS 用该权限保护 sudo 配置。",
        "ko": "macOS는 이 권한으로 sudo 설정을 보호합니다.",
        "ru": "macOS защищает настройку sudo этим разрешением.",
    },
    "setup.step.fda.waiting": {
        "en": "Turn on “MugshotHelper” in the list, then come back here.",
        "fr": "Activez « MugshotHelper » dans la liste, puis revenez ici.",
        "es": "Activa «MugshotHelper» en la lista y vuelve aquí.",
        "de": "Aktiviere „MugshotHelper“ in der Liste und komm dann zurück.",
        "it": "Attiva «MugshotHelper» nell'elenco, poi torna qui.",
        "pt-BR": "Ative “MugshotHelper” na lista e volte aqui.",
        "nl": "Schakel “MugshotHelper” in de lijst in en kom terug.",
        "ja": "リストで「MugshotHelper」をオンにして、ここに戻ってください。",
        "zh-Hans": "在列表中开启“MugshotHelper”，然后回到这里。",
        "ko": "목록에서 “MugshotHelper”를 켠 뒤 여기로 돌아오세요.",
        "ru": "Включите «MugshotHelper» в списке и вернитесь сюда.",
    },
    "setup.step.rule": {
        "en": "Write the sudo rule", "fr": "Écrire la règle sudo",
        "es": "Escribir la regla de sudo", "de": "sudo-Regel schreiben",
        "it": "Scrivi la regola sudo", "pt-BR": "Gravar a regra do sudo",
        "nl": "De sudo-regel schrijven", "ja": "sudoルールを書き込む",
        "zh-Hans": "写入 sudo 规则", "ko": "sudo 규칙 기록",
        "ru": "Записать правило sudo",
    },
    "setup.step.rule.detail": {
        "en": "Your password always stays as a fallback.",
        "fr": "Votre mot de passe reste toujours en repli.",
        "es": "Tu contraseña siempre queda como alternativa.",
        "de": "Dein Passwort bleibt immer als Rückfallebene.",
        "it": "La tua password resta sempre come ripiego.",
        "pt-BR": "Sua senha continua sempre como alternativa.",
        "nl": "Je wachtwoord blijft altijd als terugval.",
        "ja": "パスワードは常に代替手段として残ります。",
        "zh-Hans": "你的密码始终作为后备保留。",
        "ko": "암호는 항상 대체 수단으로 남습니다.",
        "ru": "Ваш пароль всегда остаётся запасным вариантом.",
    },
    "setup.open": {
        "en": "Open", "fr": "Ouvrir", "es": "Abrir", "de": "Öffnen", "it": "Apri",
        "pt-BR": "Abrir", "nl": "Openen", "ja": "開く", "zh-Hans": "打开",
        "ko": "열기", "ru": "Открыть",
    },
    "setup.done": {
        "en": "Done", "fr": "Terminé", "es": "Listo", "de": "Fertig", "it": "Fine",
        "pt-BR": "Concluir", "nl": "Klaar", "ja": "完了", "zh-Hans": "完成",
        "ko": "완료", "ru": "Готово",
    },

    # ---- menu ----
    "menu.open": {
        "en": "Open Mugshot", "fr": "Ouvrir Mugshot", "es": "Abrir Mugshot",
        "de": "Mugshot öffnen", "it": "Apri Mugshot", "pt-BR": "Abrir o Mugshot",
        "nl": "Mugshot openen", "ja": "Mugshotを開く", "zh-Hans": "打开 Mugshot",
        "ko": "Mugshot 열기", "ru": "Открыть Mugshot",
    },
    "menu.restart": {
        "en": "Restart Face ID", "fr": "Relancer Face ID", "es": "Reiniciar Face ID",
        "de": "Face ID neu starten", "it": "Riavvia Face ID", "pt-BR": "Reiniciar o Face ID",
        "nl": "Face ID herstarten", "ja": "Face IDを再起動", "zh-Hans": "重启 Face ID",
        "ko": "Face ID 다시 시작", "ru": "Перезапустить Face ID",
    },
    "menu.status.ready": {
        "en": "Ready", "fr": "Prêt", "es": "Listo", "de": "Bereit", "it": "Pronto",
        "pt-BR": "Pronto", "nl": "Klaar", "ja": "準備完了", "zh-Hans": "已就绪",
        "ko": "준비됨", "ru": "Готово",
    },
    "menu.status.stopped": {
        "en": "Stopped", "fr": "Arrêté", "es": "Detenido", "de": "Gestoppt",
        "it": "Arrestato", "pt-BR": "Parado", "nl": "Gestopt", "ja": "停止中",
        "zh-Hans": "已停止", "ko": "중지됨", "ru": "Остановлено",
    },
    "menu.status.noface": {
        "en": "No face registered", "fr": "Aucun visage enregistré",
        "es": "Ningún rostro registrado", "de": "Kein Gesicht erfasst",
        "it": "Nessun volto registrato", "pt-BR": "Nenhum rosto registrado",
        "nl": "Geen gezicht vastgelegd", "ja": "顔が未登録",
        "zh-Hans": "尚未录入面容", "ko": "등록된 얼굴 없음",
        "ru": "Лицо не зарегистрировано",
    },
    "menu.status.nosudo": {
        "en": "Not enabled for sudo", "fr": "Pas activé pour sudo",
        "es": "No activado para sudo", "de": "Für sudo nicht aktiviert",
        "it": "Non attivo per sudo", "pt-BR": "Não ativado para o sudo",
        "nl": "Niet ingeschakeld voor sudo", "ja": "sudo用に未設定",
        "zh-Hans": "未为 sudo 启用", "ko": "sudo용으로 꺼짐",
        "ru": "Для sudo не включено",
    },

    # ---- état sudo dans la fenêtre principale ----
    "set.sudo.on": {
        "en": "Enabled for sudo", "fr": "Activé pour sudo", "es": "Activado para sudo",
        "de": "Für sudo aktiviert", "it": "Attivo per sudo", "pt-BR": "Ativado para o sudo",
        "nl": "Ingeschakeld voor sudo", "ja": "sudo用に有効", "zh-Hans": "已为 sudo 启用",
        "ko": "sudo용으로 켜짐", "ru": "Включено для sudo",
    },
    "set.sudo.off": {
        "en": "Not enabled", "fr": "Non activé", "es": "No activado",
        "de": "Nicht aktiviert", "it": "Non attivo", "pt-BR": "Não ativado",
        "nl": "Niet ingeschakeld", "ja": "未設定", "zh-Hans": "未启用",
        "ko": "꺼짐", "ru": "Не включено",
    },
    "set.sudo.disable": {
        "en": "Disable", "fr": "Désactiver", "es": "Desactivar", "de": "Deaktivieren",
        "it": "Disattiva", "pt-BR": "Desativar", "nl": "Uitschakelen", "ja": "無効にする",
        "zh-Hans": "停用", "ko": "끄기", "ru": "Отключить",
    },

    # ---- sensibilité en trois crans ----
    "set.sensitivity.lenient": {
        "en": "Lenient", "fr": "Tolérant", "es": "Tolerante", "de": "Locker",
        "it": "Tollerante", "pt-BR": "Tolerante", "nl": "Soepel", "ja": "ゆるめ",
        "zh-Hans": "宽松", "ko": "느슨함", "ru": "Мягкая",
    },
    "set.sensitivity.lenient.detail": {
        "en": "Recognizes you more easily, including in poor light.",
        "fr": "Vous reconnaît plus facilement, y compris en faible lumière.",
        "es": "Te reconoce más fácilmente, incluso con poca luz.",
        "de": "Erkennt dich leichter, auch bei wenig Licht.",
        "it": "Ti riconosce più facilmente, anche con poca luce.",
        "pt-BR": "Reconhece você mais facilmente, inclusive com pouca luz.",
        "nl": "Herkent je makkelijker, ook bij weinig licht.",
        "ja": "暗い場所でも認識しやすくなります。",
        "zh-Hans": "更容易识别你，光线不足时也可以。",
        "ko": "어두운 곳에서도 더 쉽게 인식합니다.",
        "ru": "Легче узнаёт вас, в том числе при плохом освещении.",
    },
    "set.sensitivity.balanced": {
        "en": "Balanced", "fr": "Équilibré", "es": "Equilibrado", "de": "Ausgewogen",
        "it": "Bilanciato", "pt-BR": "Equilibrado", "nl": "Gebalanceerd", "ja": "標準",
        "zh-Hans": "均衡", "ko": "균형", "ru": "Сбалансированная",
    },
    "set.sensitivity.balanced.detail": {
        "en": "The recommended setting.",
        "fr": "Le réglage recommandé.",
        "es": "El ajuste recomendado.",
        "de": "Die empfohlene Einstellung.",
        "it": "L'impostazione consigliata.",
        "pt-BR": "O ajuste recomendado.",
        "nl": "De aanbevolen instelling.",
        "ja": "推奨される設定です。",
        "zh-Hans": "推荐设置。",
        "ko": "권장 설정입니다.",
        "ru": "Рекомендуемая настройка.",
    },
    "set.sensitivity.strict": {
        "en": "Strict", "fr": "Strict", "es": "Estricto", "de": "Streng",
        "it": "Severo", "pt-BR": "Rígido", "nl": "Streng", "ja": "厳格",
        "zh-Hans": "严格", "ko": "엄격", "ru": "Строгая",
    },
    "set.sensitivity.strict.detail": {
        "en": "Rejects more often, including you. Expect the password prompt more.",
        "fr": "Refuse plus souvent, vous compris. Le mot de passe reviendra plus souvent.",
        "es": "Rechaza más a menudo, a ti incluido. Verás más la contraseña.",
        "de": "Lehnt häufiger ab, auch dich. Das Passwort wird öfter verlangt.",
        "it": "Rifiuta più spesso, anche te. La password comparirà più spesso.",
        "pt-BR": "Recusa com mais frequência, inclusive você. A senha aparecerá mais.",
        "nl": "Weigert vaker, ook jou. Je krijgt vaker het wachtwoord.",
        "ja": "本人でも拒否されやすくなり、パスワード入力が増えます。",
        "zh-Hans": "拒绝更频繁，包括你本人，会更常要求输入密码。",
        "ko": "본인도 더 자주 거부되어 암호 입력이 늘어납니다.",
        "ru": "Чаще отклоняет, в том числе вас. Пароль будет запрашиваться чаще.",
    },
    "set.behavior.sensitivity.advanced": {
        "en": "Advanced", "fr": "Avancé", "es": "Avanzado", "de": "Erweitert",
        "it": "Avanzate", "pt-BR": "Avançado", "nl": "Geavanceerd", "ja": "詳細",
        "zh-Hans": "高级", "ko": "고급", "ru": "Дополнительно",
    },

    # ---- diagnostic ----
    "set.diagnose": {
        "en": "Copy diagnostics", "fr": "Copier le diagnostic",
        "es": "Copiar el diagnóstico", "de": "Diagnose kopieren",
        "it": "Copia la diagnostica", "pt-BR": "Copiar o diagnóstico",
        "nl": "Diagnose kopiëren", "ja": "診断情報をコピー",
        "zh-Hans": "复制诊断信息", "ko": "진단 정보 복사",
        "ru": "Скопировать диагностику",
    },
    "set.diagnose.running": {
        "en": "Collecting…", "fr": "Collecte en cours…", "es": "Recopilando…",
        "de": "Wird gesammelt…", "it": "Raccolta in corso…", "pt-BR": "Coletando…",
        "nl": "Verzamelen…", "ja": "収集中…", "zh-Hans": "正在收集…",
        "ko": "수집 중…", "ru": "Сбор данных…",
    },
    "set.diagnose.copied": {
        "en": "Diagnostics copied to the clipboard. Paste it into your bug report.",
        "fr": "Diagnostic copié dans le presse-papiers. Collez-le dans votre rapport.",
        "es": "Diagnóstico copiado al portapapeles. Pégalo en tu informe.",
        "de": "Diagnose in die Zwischenablage kopiert. Füge sie in deinen Bericht ein.",
        "it": "Diagnostica copiata negli appunti. Incollala nella tua segnalazione.",
        "pt-BR": "Diagnóstico copiado. Cole no seu relatório de problema.",
        "nl": "Diagnose gekopieerd naar het klembord. Plak het in je melding.",
        "ja": "診断情報をクリップボードにコピーしました。報告に貼り付けてください。",
        "zh-Hans": "诊断信息已复制到剪贴板，请粘贴到你的问题报告中。",
        "ko": "진단 정보를 클립보드에 복사했습니다. 버그 리포트에 붙여 넣으세요.",
        "ru": "Диагностика скопирована в буфер обмена. Вставьте её в отчёт.",
    },

    # ---- causes d'échec renvoyées par le moteur ----
    # Le moteur émet un code stable (`camera-unavailable`), l'app le traduit. Il
    # renvoyait auparavant des phrases françaises, affichées telles quelles dans une
    # interface anglaise.
    "err.camera-unavailable": {
        "en": "The camera is not available. Another app may be using it.",
        "fr": "La caméra n'est pas disponible. Une autre app l'utilise peut-être.",
        "es": "La cámara no está disponible. Puede que otra app la esté usando.",
        "de": "Die Kamera ist nicht verfügbar. Möglicherweise nutzt sie eine andere App.",
        "it": "La fotocamera non è disponibile. Forse è in uso da un'altra app.",
        "pt-BR": "A câmera não está disponível. Outro app pode estar usando-a.",
        "nl": "De camera is niet beschikbaar. Mogelijk gebruikt een andere app hem.",
        "ja": "カメラを使用できません。他のAppが使用中の可能性があります。",
        "zh-Hans": "摄像头不可用，可能有其他 App 正在使用。",
        "ko": "카메라를 사용할 수 없습니다. 다른 App이 사용 중일 수 있습니다.",
        "ru": "Камера недоступна. Возможно, её использует другое приложение.",
    },
    "err.not-enough-samples": {
        "en": "Not enough usable captures. Try again with more light, facing the camera.",
        "fr": "Pas assez de captures exploitables. Réessaie avec plus de lumière, face à la caméra.",
        "es": "No hay suficientes capturas útiles. Inténtalo con más luz, de frente a la cámara.",
        "de": "Zu wenige brauchbare Aufnahmen. Versuche es mit mehr Licht, direkt zur Kamera.",
        "it": "Acquisizioni utili insufficienti. Riprova con più luce, di fronte alla fotocamera.",
        "pt-BR": "Capturas úteis insuficientes. Tente com mais luz, de frente para a câmera.",
        "nl": "Te weinig bruikbare opnames. Probeer opnieuw met meer licht, recht voor de camera.",
        "ja": "有効な撮影が足りません。明るい場所でカメラに正対して再試行してください。",
        "zh-Hans": "可用采集不足。请在更明亮处正对摄像头重试。",
        "ko": "사용 가능한 촬영이 부족합니다. 더 밝은 곳에서 카메라를 정면으로 보고 다시 시도하세요.",
        "ru": "Недостаточно пригодных снимков. Попробуйте при лучшем освещении, лицом к камере.",
    },
    "err.interrupted": {
        "en": "Enrollment was interrupted.", "fr": "L'enrôlement a été interrompu.",
        "es": "El registro se interrumpió.", "de": "Die Erfassung wurde abgebrochen.",
        "it": "La registrazione è stata interrotta.", "pt-BR": "O registro foi interrompido.",
        "nl": "De registratie is onderbroken.", "ja": "登録が中断されました。",
        "zh-Hans": "录入被中断。", "ko": "등록이 중단되었습니다.",
        "ru": "Регистрация прервана.",
    },
    "err.models-missing": {
        "en": "The recognition models are missing. Reinstall Mugshot.",
        "fr": "Les modèles de reconnaissance sont introuvables. Réinstalle Mugshot.",
        "es": "Faltan los modelos de reconocimiento. Reinstala Mugshot.",
        "de": "Die Erkennungsmodelle fehlen. Installiere Mugshot neu.",
        "it": "Mancano i modelli di riconoscimento. Reinstalla Mugshot.",
        "pt-BR": "Os modelos de reconhecimento estão ausentes. Reinstale o Mugshot.",
        "nl": "De herkenningsmodellen ontbreken. Installeer Mugshot opnieuw.",
        "ja": "認識モデルが見つかりません。Mugshotを再インストールしてください。",
        "zh-Hans": "找不到识别模型，请重新安装 Mugshot。",
        "ko": "인식 모델을 찾을 수 없습니다. Mugshot을 다시 설치하세요.",
        "ru": "Модели распознавания не найдены. Переустановите Mugshot.",
    },

    # ---- invites affichées par le moteur pendant un `sudo` (→ i18n/engine.json) ----
    "engine.prompt.title": {
        "en": "Authentication required", "fr": "Authentification requise",
        "es": "Autenticación requerida", "de": "Authentifizierung erforderlich",
        "it": "Autenticazione richiesta", "pt-BR": "Autenticação necessária",
        "nl": "Verificatie vereist", "ja": "認証が必要です",
        "zh-Hans": "需要验证", "ko": "인증이 필요합니다",
        "ru": "Требуется аутентификация",
    },
    "engine.prompt.subtitle": {
        "en": "sudo wants to verify your identity",
        "fr": "sudo souhaite vérifier votre identité",
        "es": "sudo quiere verificar tu identidad",
        "de": "sudo möchte deine Identität überprüfen",
        "it": "sudo vuole verificare la tua identità",
        "pt-BR": "o sudo quer verificar sua identidade",
        "nl": "sudo wil je identiteit verifiëren",
        "ja": "sudoがあなたの本人確認を求めています",
        "zh-Hans": "sudo 需要验证你的身份",
        "ko": "sudo가 본인 확인을 요청합니다",
        "ru": "sudo хочет подтвердить вашу личность",
    },
    "engine.btn.face": {
        "en": "Use Face ID", "fr": "Utiliser Face ID", "es": "Usar Face ID",
        "de": "Face ID verwenden", "it": "Usa Face ID", "pt-BR": "Usar o Face ID",
        "nl": "Face ID gebruiken", "ja": "Face IDを使用", "zh-Hans": "使用 Face ID",
        "ko": "Face ID 사용", "ru": "Использовать Face ID",
    },
    "engine.btn.touch": {
        "en": "Use fingerprint", "fr": "Utiliser l'empreinte", "es": "Usar la huella",
        "de": "Fingerabdruck verwenden", "it": "Usa l'impronta", "pt-BR": "Usar a digital",
        "nl": "Vingerafdruk gebruiken", "ja": "指紋を使用", "zh-Hans": "使用指纹",
        "ko": "지문 사용", "ru": "Использовать отпечаток",
    },
    "engine.btn.password": {
        "en": "Enter password", "fr": "Saisir le mot de passe", "es": "Escribir la contraseña",
        "de": "Passwort eingeben", "it": "Inserisci la password", "pt-BR": "Digitar a senha",
        "nl": "Wachtwoord invoeren", "ja": "パスワードを入力", "zh-Hans": "输入密码",
        "ko": "암호 입력", "ru": "Ввести пароль",
    },
    "engine.touchid.reason": {
        "en": "unlock sudo", "fr": "déverrouiller sudo", "es": "desbloquear sudo",
        "de": "sudo entsperren", "it": "sbloccare sudo", "pt-BR": "desbloquear o sudo",
        "nl": "sudo ontgrendelen", "ja": "sudoのロックを解除", "zh-Hans": "解锁 sudo",
        "ko": "sudo 잠금 해제", "ru": "разблокировать sudo",
    },

    "set.msg.approve": {
        "en": "Approve Mugshot in Settings › General › Login Items, then toggle again.",
        "fr": "Autorise Mugshot dans Réglages › Général › Ouverture, puis réactive.",
        "es": "Autoriza Mugshot en Ajustes › General › Ítems de inicio, luego reactiva.",
        "de": "Erlaube Mugshot in Einstellungen › Allgemein › Anmeldeobjekte, dann erneut.",
        "it": "Autorizza Mugshot in Impostazioni › Generali › Elementi login, poi riattiva.",
        "pt-BR": "Autorize o Mugshot em Ajustes › Geral › Itens de início e ative de novo.",
        "nl": "Sta Mugshot toe in Instellingen › Algemeen › Inlogitems, dan opnieuw.",
        "ja": "設定 › 一般 › ログイン項目でMugshotを許可し、もう一度切り替えてください。",
        "zh-Hans": "在设置 › 通用 › 登录项中允许 Mugshot，然后重新开启。",
        "ko": "설정 › 일반 › 로그인 항목에서 Mugshot을 허용한 뒤 다시 켜세요.",
        "ru": "Разрешите Mugshot в Настройках › Основные › Объекты входа, затем снова.",
    },
}


def escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def main():
    for lang in LANGS:
        d = OUT / f"{lang}.lproj"
        d.mkdir(parents=True, exist_ok=True)
        lines = ['/* Mugshot — auto-généré par make_i18n.py */']
        for key, tr in TR.items():
            val = tr.get(lang, tr["en"])
            lines.append(f'"{key}" = "{escape(val)}";')
        (d / "Localizable.strings").write_text("\n".join(lines) + "\n", encoding="utf-8")

    engine = {lang: {k: TR[k].get(lang, TR[k]["en"]) for k in ENGINE_KEYS}
              for lang in LANGS}
    (OUT / "engine.json").write_text(
        json.dumps(engine, ensure_ascii=False, indent=1, sort_keys=True) + "\n",
        encoding="utf-8")

    print(f"{len(TR)} clés × {len(LANGS)} langues → {OUT}")
    print(f"{len(ENGINE_KEYS)} clés moteur → {OUT / 'engine.json'}")


if __name__ == "__main__":
    main()
