# Larpsec 2.3 para Matcha

Selector cosmético local para Murder Duels. El panel negro aparece al ejecutar; **Right Shift** lo abre y lo oculta. Elige una skin y cambia de arma normalmente para que el juego reconstruya el modelo.

## Ejecutar desde una URL

Pega esta línea en el editor Lua de Matcha, dentro de Murder Duels:

```lua
loadstring(httpget("https://raw.githubusercontent.com/JoelllL-U/Filegame/refs/heads/main/larpsec/Larpsec.lua"))()
```

No se ejecuta en PowerShell. No hace falta copiar Larpsec.lua al PC ni mantener un servidor local. Matcha sigue siendo necesario. El script crea automáticamente el perfil y la caché en `C:\matcha\workspace\Larpsec`.

## Activación

| Función | Requisito |
|---|---|
| Panel, IDs de hasta 15 caracteres, perfil y Auto Apply | Drawing, UI Binding y archivos de Matcha; sin Hybrid ni Unsafe. |
| IDs largos | **Allow Unsafe LuaU** en Matcha y **Extended skins = ON** en Larpsec. Si no se valida la disposición de memoria, esas skins no aparecen. |
| Iconos inferiores | Hotbar skin icons = ON, imágenes descargadas, Roblox en primer plano y panel cerrado. La LuaVM confirma la misma posición absoluta del icono nativo y vuelve a localizar las ranuras cuatro veces por segundo; la captura visual no estuvo disponible en esta sesión. |
| Acento 2D de eliminación | Opción independiente en Kill Effects. No equivale al finisher nativo. |

Larpsec no llama FireServer ni InvokeServer. Hybrid no es necesario para las funciones implementadas; durante las pruebas ya estaba activado y no se cambió esa preferencia.

## IDs largos

El fallo de 15 caracteres se encontró en las escrituras de cadenas de esta instalación de Matcha. No es un límite de los IDs del juego. El modo extendido asigna temporalmente un nombre corto a la plantilla original y a los paquetes asociados de sonido, animación y equipamiento que encuentra. El juego continúa construyendo el arma con sus piezas y uniones. El perfil conserva el ID verdadero.

Las plantillas permanecen en sus carpetas y no se modifica su geometría. Las direcciones se vuelven a validar en cada ejecución. Los nombres se restauran al elegir otra skin o descargar Larpsec.

**Este modo es experimental y escribe memoria. Una actualización de Roblox o cerrar la VM a la fuerza puede dejar cambios locales o provocar un cierre. Ejecuta `Larpsec.Unload()` antes de desactivar Unsafe LuaU.** Si falla la restauración, habilita Unsafe de nuevo y llama a Unload; si no se recupera, reinicia Roblox.

Si otro jugador usa la misma plantilla original, Larpsec rechaza o suspende el cambio extendido para evitar alterar su apariencia local. Puedes reintentar seleccionando la skin más tarde.

## Guardado

El perfil conserva las dos skins, favoritos, Auto Apply y preferencias. Auto Apply apagado conserva el loadout sin aplicarlo al siguiente inicio. Elegir una skin manualmente sigue funcionando durante la sesión. Restaurar originales conserva la selección guardada. Cada guardado verifica la escritura y mantiene una copia anterior válida.

## Comprobado y pendiente

- Guardado, recarga con Auto Apply activado y apagado, recarga de un ID largo y limpieza de los dibujos registrados: comprobados. La versión 2.3 registra 350 dibujos, incluidos los fondos de los iconos.
- Omega Energy Blade, Green Energy Blade y Omega Energy Blaster: reconstrucción nativa comprobada; sus cantidades de MeshPart coinciden con las plantillas. Blue Energy Blaster fue rechazada correctamente por conflicto con otro jugador. Las demás skins largas no están certificadas individualmente.
- **Geometría de iconos:** en Viewport `1002x750`, la posición de dibujo coincidió con `WeaponIcon.AbsolutePosition` en las dos ranuras (`336.78,533.39` y `413.61,526.63`); las imágenes personalizadas cargaron y se estimó el tamaño desde el margen real de la ranura (`64x64`). Las máscaras ahora llegan hasta ese mismo borde y las referencias se renuevan cada 0.25 s para seguir cambios de la GUI. No tuve captura de Roblox disponible en esta sesión, así que no afirmo que la cobertura visual ni el menú de ventajas estén verificados píxel por píxel.
- **Finishers nativos sin resolver:** Kill Effects muestra recursos y permite feedback 2D, pero no reproduce ni equipa el finisher del juego. Los paquetes nativos existen en el cliente, pero Matcha no ejecuta `ModuleScript` de Roblox desde `require` y no expone `Instance.new`, `Clone` ni `Destroy`, que necesita el reproductor del juego. Hybrid habilita llamadas remotas, pero eso modificaría el flujo del servidor y no es una solución client-only. El acento 2D no equivale al efecto nativo.
- **Repeticiones:** los cambios cosméticos se pausan al entrar y se reanudan al salir; esta transición se comprobó. La selección guardada se conserva. El arma invisible persistió en la grabación probada después de descargar Larpsec y restaurar los atributos originales a Default. No se ha corregido esa invisibilidad ni se muestran las skins personalizadas en replay. Los actores usan datos separados de LocalPlayer.
- Los paquetes de sonido y animación se conservan y se resuelven mediante el nombre corto cuando están disponibles. No se ha probado cada disparo, estela, animación, sonido o evento de muerte de cada skin. No se promete equivalencia completa.

No se inició ningún duelo. Una prueba descartada de mover una copia dejó una referencia vacía en el personaje de práctica; el personaje se regeneró y esa técnica no forma parte del producto.

## MCP para continuar el desarrollo

Con Roblox y Matcha abiertos y el bridge habilitado, su dirección es `http://127.0.0.1:8765/mcp`. Para registrarlo desde una terminal con Codex CLI instalado:

```text
codex mcp add matcha --url http://127.0.0.1:8765/mcp
```

El MCP sirve para investigar durante el desarrollo. No hace falta para ejecutar el loader.

Referencias: [memoria y riesgos](https://huoadf.github.io/matcha-docs/memory/), [API e Hybrid](https://huoadf.github.io/matcha-docs/classes/), [require y ejecución protegida](https://huoadf.github.io/matcha-docs/functions-misc/). Las pruebas de la instalación tienen prioridad cuando las referencias difieren.

