# Larpsec 2.1 para Matcha

Selector cosmético local para Murder Duels. El panel negro aparece al ejecutar; **Right Shift** lo abre y lo oculta. Elige una skin y cambia de arma normalmente para que el juego reconstruya el modelo.

## Ejecutar desde una URL

Pega esta línea en el editor Lua de Matcha, dentro de Murder Duels:

```lua
loadstring(httpget("https://raw.githubusercontent.com/JoelllL-U/Filegame/main/larpsec/Larpsec.lua"))()
```

No se ejecuta en PowerShell. No hace falta copiar Larpsec.lua al PC ni mantener un servidor local. Matcha sigue siendo necesario. El script crea automáticamente el perfil y la caché en `C:\matcha\workspace\Larpsec`.

## Activación

| Función | Requisito |
|---|---|
| Panel, IDs de hasta 15 caracteres, perfil y Auto Apply | Drawing, UI Binding y archivos de Matcha; sin Hybrid ni Unsafe. |
| IDs largos | **Allow Unsafe LuaU** en Matcha y **Extended skins = ON** en Larpsec. Si no se valida la disposición de memoria, esas skins no aparecen. |
| Iconos inferiores | Hotbar skin icons = ON, imágenes descargadas, Roblox en primer plano y panel cerrado. Aún pendientes de confirmación visual. |
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

- Guardado, recarga con Auto Apply activado y apagado, recarga de un ID largo y limpieza de los 346 dibujos registrados: comprobados.
- Omega Energy Blade, Green Energy Blade y Omega Energy Blaster: reconstrucción nativa comprobada; sus cantidades de MeshPart coinciden con las plantillas. Blue Energy Blaster fue rechazada correctamente por conflicto con otro jugador. Las demás skins largas no están certificadas individualmente.
- **Iconos inferiores sin resolver:** se corrigió la posición vertical y se reforzó la limpieza. Las imágenes cargan, pero el usuario indicó que aún no se ven.
- **Finishers nativos sin resolver:** Kill Effects muestra los recursos encontrados y permite feedback 2D. No ejecuta ni equipa los efectos nativos. Sus módulos visuales son locales, pero esta API no permite invocarlos directamente. La afirmación anterior de que todos eran exclusivamente del servidor era demasiado amplia.
- **Repeticiones sin resolver:** los actores de replay usan datos separados de LocalPlayer. Esta versión no modifica la grabación ni garantiza corregir el arma invisible o la mira.
- Los paquetes de sonido y animación se conservan y se resuelven mediante el nombre corto cuando están disponibles. No se ha probado cada disparo, estela, animación, sonido o evento de muerte de cada skin. No se promete equivalencia completa.

No se inició ningún duelo. Una prueba descartada de mover una copia dejó una referencia vacía en el personaje de práctica; el personaje se regeneró y esa técnica no forma parte del producto.

## MCP para continuar el desarrollo

Con Roblox y Matcha abiertos y el bridge habilitado, su dirección es `http://127.0.0.1:8765/mcp`. Para registrarlo desde una terminal con Codex CLI instalado:

```text
codex mcp add matcha --url http://127.0.0.1:8765/mcp
```

El MCP sirve para investigar durante el desarrollo. No hace falta para ejecutar el loader.

Referencias: [memoria y riesgos](https://huoadf.github.io/matcha-docs/memory/), [API e Hybrid](https://huoadf.github.io/matcha-docs/classes/), [require y ejecución protegida](https://huoadf.github.io/matcha-docs/functions-misc/). Las pruebas de la instalación tienen prioridad cuando las referencias difieren.
