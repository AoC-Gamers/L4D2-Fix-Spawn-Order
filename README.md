# 🎯 L4D2 Fix Spawn Order Plugin
[![Left4DHooks](https://img.shields.io/badge/Left4DHooks-Required-red.svg)](https://forums.alliedmods.net/showthread.php?t=321696)
[![Version](https://img.shields.io/badge/Version-4.5-green.svg)](https://github.com/AoC-Gamers/L4D2-Fix-Spawn-Order/releases)
[![License](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)

Un plugin completo para Left 4 Dead 2 que implementa un **sistema de rotación natural** para Special Infected, permitiendo que los **quad-caps se desarrollen espontáneamente** sin forzarlos artificialmente.

## 🚀 Características Principales

- **🔄 Rotación Natural**: Los quad-caps emergen orgánicamente del orden de muertes
- **⚖️ Sistema Dual**: Separación entre longitud de cola (`z_versus_*_limit`) y capacidad de spawn (`z_max_player_zombies`)
- **🤖 Integración de Bots**: Soporte transparente para equipos mixtos (humanos + bots)
- **📊 Análisis Avanzado**: Comandos detallados para monitoreo y debugging
- **🎮 Competitivo**: Compatible con configuraciones competitivas estándar

## 📥 Instalación Rápida

```bash
# Descargar y copiar al servidor
cp l4d2_fix_spawn_order.smx addons/sourcemod/plugins/optional/
```

### Configuración Mínima
```cfg
// En tu server.cfg o competitive config
z_versus_hunter_limit 1
z_versus_boomer_limit 1  
z_versus_smoker_limit 1
z_versus_jockey_limit 1
z_versus_charger_limit 1
z_versus_spitter_limit 1
z_max_player_zombies 4
```

## 💡 Ejemplo de Comportamiento

```
Estado inicial: [Smoker, Boomer, Hunter, Jockey, Charger, Spitter]

1. Boomer muere → Respawnea como Hunter
   Cola: [Smoker, Hunter, Jockey, Charger, Spitter, Boomer] 
   Primeros 4: [Smoker, Hunter, Jockey, Charger] → ✅ QUAD-CAP NATURAL

2. Spitter muere → Respawnea como Smoker
   Cola: [Hunter, Jockey, Charger, Boomer, Smoker, Spitter]
   Primeros 4: [Hunter, Jockey, Charger, Boomer] → 3 dominadores + 1 no-dominador
```
## 📚 Documentación Detallada

- **[🏗️ Arquitectura](docs/ARCHITECTURE.md)** - Estructura técnica y algoritmos
- **[🔄 Flujo del Plugin](docs/PLUGIN_FLOW.md)** - Explicación detallada del funcionamiento interno

## 🙏 Créditos

- [Proyecto original de SirPlease](https://github.com/SirPlease/L4D2-Competitive-Rework)
