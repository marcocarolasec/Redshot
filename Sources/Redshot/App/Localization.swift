import Combine
import Foundation

/// Idioma de la interfaz. Inglés es el idioma base (las cadenas en código están en inglés);
/// el español se resuelve con la tabla de abajo. Cambia en caliente: las vistas observan `Localizer.shared`.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, es
    var id: String { rawValue }
}

@MainActor
final class Localizer: ObservableObject {
    static let shared = Localizer()
    static let prefKey = "appLanguage"

    @Published private(set) var effective: String = "en"

    var setting: AppLanguage {
        get { AppLanguage(rawValue: UserDefaults.standard.string(forKey: Self.prefKey) ?? "") ?? .system }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.prefKey)
            recompute()
        }
    }

    private init() { recompute() }

    private func recompute() {
        switch setting {
        case .en: effective = "en"
        case .es: effective = "es"
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            effective = preferred.hasPrefix("es") ? "es" : "en"
        }
    }

    func translate(_ english: String) -> String {
        guard effective == "es" else { return english }
        return Self.spanish[english] ?? english
    }

    // MARK: - Tabla inglés → español

    static let spanish: [String: String] = [
        // Menú de barra
        "History": "Historial",
        "How to use…": "Cómo se usa…",
        "Capture area": "Capturar región",
        "Capture window": "Capturar ventana",
        "Capture full screen": "Capturar pantalla completa",
        "Recent": "Recientes",
        "Pause clipboard": "Pausar portapapeles",
        "Settings…": "Ajustes…",
        "Quit Redshot": "Salir de Redshot",

        // Tipos
        "Text": "Texto",
        "Link": "Enlace",
        "Code": "Código",
        "Color": "Color",
        "Image": "Imagen",
        "File": "Archivo",
        "Screenshot": "Captura",

        // Historial
        "Search text, OCR, app…": "Buscar en texto, OCR, app…",
        "All types": "Todos",
        "All apps": "Todas las apps",
        "Capture": "Capturar",
        "Area  ⌃⌘S": "Región  ⌃⌘S",
        "Window  ⌃⌘W": "Ventana  ⌃⌘W",
        "Full screen  ⌃⌘F": "Pantalla completa  ⌃⌘F",
        "Nothing saved yet": "Todavía no hay nada guardado",
        "No results": "Sin resultados",
        "Copy something or take a screenshot with ⌃⌘S": "Copia algo o haz una captura con ⌃⌘S",
        "%d items": "%d elementos",
        "Clear (keeps pinned)": "Vaciar (mantiene fijados)",
        "Settings": "Ajustes",

        // Tarjeta
        "Edit…": "Editar…",
        "Copy": "Copiar",
        "Copy and paste": "Copiar y pegar",
        "Copy text (OCR)": "Copiar texto (OCR)",
        "Unpin": "Desfijar",
        "Pin": "Fijar",
        "Category": "Categoría",
        "Work": "Trabajo",
        "Personal": "Personal",
        "Pentest": "Pentest",
        "Blog": "Blog",
        "Client": "Cliente",
        "Remove category": "Quitar categoría",
        "Open": "Abrir",
        "Show in Finder": "Mostrar en Finder",
        "Open link": "Abrir enlace",
        "Delete": "Eliminar",

        // Ajustes
        "Redshot Settings": "Ajustes de Redshot",
        "General": "General",
        "Clipboard": "Portapapeles",
        "Screenshots": "Capturas",
        "Shortcuts": "Atajos",
        "Language": "Idioma",
        "System": "Sistema",
        "Open Redshot at login": "Abrir Redshot al iniciar sesión",
        "Show the welcome guide at launch": "Mostrar la guía de bienvenida al arrancar",
        "Permissions": "Permisos",
        "Screen Recording": "Grabación de pantalla",
        "Required to take screenshots.": "Necesario para capturar.",
        "Accessibility": "Accesibilidad",
        "To paste directly when you pick an item.": "Para pegar directamente al elegir un elemento.",
        "If you just granted Screen Recording, restart Redshot to apply it.": "Si acabas de conceder Grabación de pantalla, reinicia Redshot para que se aplique.",
        "Granted": "Concedido",
        "Grant…": "Conceder…",
        "History size": "Historial",
        "500 items": "500 elementos",
        "1,000 items": "1.000 elementos",
        "2,500 items": "2.500 elementos",
        "5,000 items": "5.000 elementos",
        "10,000 items": "10.000 elementos",
        "Open the welcome guide…": "Abrir la guía de bienvenida…",
        "Above the limit the oldest items are removed. Pinned items are never removed.": "Al superar el límite se borran los más antiguos. Los fijados nunca se borran.",
        "Save what I copy": "Guardar lo que copio",
        "Paste directly when I pick an item": "Pegar directamente al elegir un elemento",
        "Don't save content that looks sensitive": "No guardar contenido que parezca sensible",
        "Sensitive: API tokens, private keys, JWTs and valid card numbers. Anything 1Password or Bitwarden mark as concealed is never saved.": "Sensible: tokens de API, claves privadas, JWT y números de tarjeta válidos. Lo que 1Password o Bitwarden marcan como confidencial nunca se guarda.",
        "Ignored apps": "Apps ignoradas",
        "One app identifier per line (for example com.apple.Terminal). Nothing copied from these apps is saved.": "Un identificador de app por línea (por ejemplo com.apple.Terminal). Lo copiado desde estas apps no se guarda.",
        "Open the editor after capturing": "Abrir el editor después de capturar",
        "Copy the screenshot to the clipboard": "Copiar la captura al portapapeles",
        "Capture sound": "Sonido al capturar",
        "Recognize text in screenshots (OCR)": "Reconocer texto en las capturas (OCR)",
        "The editor offers arrows, shapes, text, pixelation and cropping; saving creates a new item and keeps the original. With OCR you can search the text inside images.": "El editor permite flechas, formas, texto, pixelado y recorte; al guardar crea un nuevo elemento y conserva el original. Con OCR puedes buscar por el texto que aparece dentro de las imágenes.",
        "Also save to": "Guardar también en",
        "No folder": "Ninguna carpeta",
        "Choose…": "Elegir…",
        "Choose": "Elegir",
        "Remove": "Quitar",
        "Screenshots always stay in the history. This adds a PNG copy in the folder you choose.": "Las capturas siempre quedan en el historial. Esto añade una copia PNG en la carpeta que elijas.",
        "Open or close the history": "Abrir o cerrar el historial",
        "Paste the 1st…9th most recent item": "Pegar el 1º…9º elemento más reciente",
        "Paste the 10th": "Pegar el 10º",
        "While capturing an area: Space switches to window mode, Esc cancels. In the history: Enter pastes the first result, Esc closes.": "Durante la captura de región: Espacio cambia a modo ventana, Esc cancela. En el historial: Enter pega el primer resultado, Esc cierra.",

        // Bienvenida
        "Screenshots and clipboard with history.\nEverything stays on your Mac.": "Capturas y portapapeles con historial.\nTodo se queda en tu Mac.",
        "Permission to capture": "Permiso para capturar",
        "Granted. You can capture now.": "Concedido. Ya puedes capturar.",
        "Granted. Just restart.": "Concedido. Solo falta reiniciar.",
        "macOS asks every app that takes screenshots for the Screen Recording permission. It's the same one Zoom or CleanShot use.": "macOS pide el permiso de Grabación de pantalla a cualquier app que haga capturas. Es el mismo que usan Zoom o CleanShot.",
        "Grant permission": "Conceder permiso",
        "System Settings opens. Turn on the Redshot switch and come back here.": "Se abre Ajustes del Sistema. Activa el interruptor de Redshot y vuelve aquí.",
        "Restart Redshot": "Reiniciar Redshot",
        "macOS applies this permission on restart. It reopens by itself at this point.": "macOS aplica este permiso al reiniciar. Vuelve a abrirse solo en este punto.",
        "Direct paste": "Pegado directo",
        "Done. Picking something from the history pastes it where you were.": "Listo. Al elegir algo del historial se pega donde estabas.",
        "Optional: with the Accessibility permission, picking something from the history pastes it directly into the app you were using.": "Opcional: con el permiso de Accesibilidad, elegir algo del historial lo pega directamente en la app en la que estabas.",
        "If you'd rather paste with ⌘V yourself, press Skip.": "Si prefieres pegar tú con ⌘V, pulsa Omitir.",
        "Screenshot saved": "Captura guardada",
        "Take a screenshot": "Haz una captura",
        "It's in the history and on the clipboard. The editor opens by itself after each capture to annotate, pixelate or crop.": "Está en el historial y en el portapapeles. El editor se abre solo tras cada captura para anotar, pixelar o recortar.",
        "Press ⌃⌘S or the button. Drag over what you want to capture.": "Pulsa ⌃⌘S o el botón. Arrastra sobre lo que quieras capturar.",
        "Capture now": "Capturar ahora",
        "The capture permission from the previous step is missing.": "Falta el permiso de captura del paso anterior.",
        "All set": "Todo listo",
        "Redshot lives in the menu bar, top right, with this icon:": "Redshot vive en la barra de menús, arriba a la derecha, con este icono:",
        "Capture area (goes to the clipboard)": "Capturar región (va al portapapeles)",
        "Open the history": "Abrir el historial",
        "Back": "Atrás",
        "Get started": "Empezar",
        "Next": "Siguiente",
        "Skip for now": "Omitir por ahora",
        "Skip": "Omitir",
        "Show at launch": "Mostrar al arrancar",
        "Open history": "Abrir historial",
        "Close": "Cerrar",

        // Editor
        "Edit screenshot": "Editar captura",
        "Select": "Seleccionar",
        "Arrow": "Flecha",
        "Line": "Línea",
        "Rectangle": "Rectángulo",
        "Ellipse": "Elipse",
        "Pixelate": "Pixelar",
        "Highlight": "Resaltar",
        "Crop": "Recortar",
        "Click to select, drag to move, Delete to remove.": "Clic para seleccionar, arrastra para mover, Supr para borrar.",
        "Drag from the start to the tip.": "Arrastra desde el origen hasta la punta.",
        "Drag to draw. Hold ⇧ for a square or circle.": "Arrastra para dibujar. Mantén ⇧ para forzar cuadrado o círculo.",
        "Click where you want to type. Enter to confirm.": "Clic donde quieras escribir. Enter para confirmar.",
        "Drag over what you want to hide (credentials, IPs, names).": "Arrastra sobre la zona que quieras ocultar (credenciales, IPs, nombres).",
        "Drag over what you want to highlight.": "Arrastra sobre lo que quieras resaltar.",
        "Drag to choose the final area. Applied when saving.": "Arrastra para elegir el área final. Se aplica al guardar.",
        "Thin": "Fino",
        "Normal": "Normal",
        "Thick": "Grueso",
        "Very thick": "Muy grueso",
        "Stroke width": "Grosor del trazo",
        "Text S": "Texto S",
        "Text M": "Texto M",
        "Text L": "Texto L",
        "Text XL": "Texto XL",
        "Text size": "Tamaño del texto",
        "Undo (⌘Z)": "Deshacer (⌘Z)",
        "Redo (⇧⌘Z)": "Rehacer (⇧⌘Z)",
        "Remove crop": "Quitar recorte",
        "Cancel": "Cancelar",
        "Export…": "Exportar…",
        "Copies the result to the clipboard and closes, without saving it to the history": "Copia el resultado al portapapeles y cierra, sin guardarlo en el historial",
        "Save": "Guardar",
        "Saves as a new history item, copies it to the clipboard and closes": "Guarda como nuevo elemento del historial, lo copia al portapapeles y cierra",
        "Discard changes?": "¿Descartar los cambios?",
        "Discard": "Descartar",
        "Keep editing": "Seguir editando",
        "⇧ forces square, circle or 45°  ·  Delete removes the selection  ·  ⌘Z undoes": "⇧ fuerza cuadrado, círculo o 45°  ·  Supr borra la selección  ·  ⌘Z deshace",

        // Instalador
        "Move Redshot to Applications?": "¿Mover Redshot a Aplicaciones?",
        "It's running from %@. To work reliably and keep its permissions, it should be in the Applications folder.": "Se está ejecutando desde %@. Para que funcione siempre y conserve los permisos, conviene que esté en la carpeta Aplicaciones.",
        "a disk image": "una imagen de disco",
        "the Downloads folder": "la carpeta Descargas",
        "Move to Applications": "Mover a Aplicaciones",
        "Not now": "Ahora no",
        "Couldn't move the app": "No se pudo mover la app",
    ]
}

/// Atajo para traducir una cadena de la interfaz.
@MainActor
func L(_ english: String) -> String {
    Localizer.shared.translate(english)
}

@MainActor
func LF(_ english: String, _ args: CVarArg...) -> String {
    String(format: Localizer.shared.translate(english), arguments: args)
}
