# Meshmerizer - Visualizador e Animador 3D com Motion Capture

<p align="center">
<img width="248.5" height="248.5" alt="icon_v2" src="https://github.com/user-attachments/assets/4d53b27d-b57d-4850-a27a-9f773821fd98" />
</p>

## 📋 Sobre o Projeto

**Meshmerizer** é uma aplicação móvel desenvolvida em Flutter que permite aos usuários visualizar modelos 3D no formato `.glb` e animá-los através de captura de movimento (motion capture) a partir de vídeos. O projeto utiliza inteligência artificial para detectar poses humanas em vídeos e transferir esses movimentos para modelos 3D rigged, criando animações rápidas que podem ser usadas em projetos diversos.

<p align="center">
  
![gif-use-1](https://github.com/user-attachments/assets/ca823e52-1ea2-4dde-a6da-3d3d4498818b)
![gif-use-2](https://github.com/user-attachments/assets/57300302-0302-4e59-b8cd-e7bcc0b2e6b6)
![gif-use-3](https://github.com/user-attachments/assets/f9077f85-be35-4910-b7e6-01613aa13448)
![gif-use-4](https://github.com/user-attachments/assets/5c834212-9c79-4ee5-ac88-117337a236e8)

</p>

### Objetivo Principal

Democratizar a criação de animações 3D, permitindo que usuários sem conhecimento técnico avançado possam:
- Carregar e visualizar modelos 3D personalizados
- Capturar movimentos humanos de vídeos comuns
- Aplicar essas animações a avatares 3D
- Exportar modelos animados para uso em outros projetos

---

## Tecnologias Utilizadas

### Frontend & Framework
- **Flutter** (Dart 3.10.3) - Framework multiplataforma para desenvolvimento mobile
- **WebView Flutter** - Renderização de conteúdo HTML/JavaScript dentro do app

### Renderização 3D
- **Three.js** (v0.160.0) - Biblioteca JavaScript para renderização 3D no navegador
- **GLTFLoader** - Carregamento de modelos 3D no formato GLTF/GLB
- **OrbitControls** - Controles de câmera para navegação 3D
- **SkeletonHelper** - Visualização da estrutura de ossos (rig) dos modelos

### Inteligência Artificial
- **Google ML Kit Pose Detection** - Detecção de poses humanas em imagens/vídeos
  - Modelo: `PoseDetectionModel.accurate`
  - Detecção de 33 landmarks corporais
  - Estimativa de profundidade (eixo Z)

### Processamento de Vídeo
- **FFmpeg Kit Flutter** - Extração de frames de vídeos
  - Taxa de captura: 10 fps
  - Formato de saída: JPEG

### Matemática 3D
- **vector_math** - Operações com vetores, quaternions e matrizes
  - Cálculos de rotação de ossos
  - Interpolação de movimentos
  - Conversão entre sistemas de coordenadas

### Manipulação de Dados
- **shared_preferences** - Armazenamento local de preferências (tutorial)
- **file_picker** - Seleção de arquivos do dispositivo

### Utilitários
- **path_provider** - Acesso a diretórios do sistema
- **url_launcher** - Abertura de URLs externas

---

## Funcionalidades Principais

### 1. Carregamento de Modelos 3D
- Suporte para arquivos `.glb` (GLTF Binary)
- Validação de formato de arquivo
- Centralização automática do modelo na viewport
- Cálculo de estatísticas (vértices e faces)

### 2. Visualização Interativa
- Controles de câmera orbital (rotação, zoom, pan)
- Iluminação configurável:
  - Posição (X, Y, Z)
  - Intensidade
  - Cor (branco, âmbar, azul, vermelho)
- Toggle de visualização do esqueleto (rig)

### 3. Sistema de Animação
- Reprodução de animações pré-existentes no modelo
- Controles de playback:
  - Play/Pause
  - Reset
  - Velocidade (0.1x a 3.0x)

### 4. Motion Capture via Vídeo
- Upload de vídeos `.mp4`
- Processamento com IA para detecção de poses
- Mapeamento de 18+ ossos principais:
  - **Torso**: Hips, Spine, Spine01, Spine02
  - **Cabeça/Pescoço**: neck, Head
  - **Braços**: Shoulders, Arms, ForeArms (esquerdo/direito)
  - **Pernas**: UpLeg, Leg (esquerdo/direito)

### 5. Parâmetros Ajustáveis de Motion Capture
- **Fator de Profundidade (Z Impact)**: 0.0 - 2.0
  - Controla a intensidade de movimento no eixo Z
- **Suavização de Movimento**: 0.01 - 1.0
  - Reduz tremores através de interpolação linear
- **Limiar de Confiança**: 0.1 - 0.95
  - Define o rigor da IA para aceitar detecções

### 6. Exportação
- Exportação de modelos animados em formato `.glb`
- Preservação de todas as animações criadas

---

## Metodologias e Conhecimentos Aplicados

### 1. Engenharia de Software
- **Arquitetura MVC**: Separação entre lógica de negócio (Dart) e apresentação (Three.js)
- **State Management**: Uso de `StatefulWidget` para gerenciar estado complexo
- **Bridge Pattern**: Comunicação Dart ↔ JavaScript via `JavaScriptChannel`
- **Async Programming**: Uso extensivo de `Future` e `async/await`

### 2. Computação Gráfica 3D
- **Sistema de Coordenadas**: Conversão entre sistemas de coordenadas da IA e do Three.js
- **Quaternions**: Representação de rotações 3D sem gimbal lock
- **Hierarquia de Transformações**: Propagação de rotações através da cadeia de ossos
- **Keyframe Animation**: Criação de animações através de keyframes de rotação

### 3. Visão Computacional & IA
- **Pose Estimation**: Detecção de landmarks corporais em 2D/3D
- **Confiança de Detecção**: Uso de likelihood para filtrar detecções ruins
- **Interpolação de Dados Faltantes**: Manutenção da última pose válida quando a detecção falha

### 4. Matemática Aplicada
- **Álgebra Linear**:
  - Normalização de vetores
  - Produto escalar e vetorial
  - Transformações de base
- **Quaternions**:
  - Rotações em 3D
  - Interpolação esférica (SLERP implícita)
  - Composição de rotações
- **Interpolação Linear (LERP)**: Suavização de movimentos

### 5. Otimização de Performance
- **Taxa de Frames Reduzida**: 10 fps para processamento de vídeo
- **Processamento em Lote**: Todas as frames processadas antes da geração da animação
- **Reutilização de Cálculos**: Cache de vetores suavizados

### 6. UX/UI Design
- **Onboarding**: Tutorial de boas-vindas na primeira execução
- **Feedback Visual**: Loading dialogs durante processamento
- **Validação de Entrada**: Verificação de formato de arquivo
- **Tooltips Informativos**: Explicações contextuais para parâmetros técnicos

---

## Pipeline de Motion Capture

```
1. Upload de Vídeo (.mp4)
         ↓
2. Extração de Frames (FFmpeg - 10 fps)
         ↓
3. Detecção de Pose por Frame (ML Kit)
         ↓
4. Cálculo de Direções de Ossos
         ↓
5. Conversão para Quaternions
         ↓
6. Aplicação de Offsets de Calibração
         ↓
7. Suavização Temporal (LERP)
         ↓
8. Geração de Keyframes (Three.js)
         ↓
9. Criação de AnimationClip
         ↓
10. Reprodução no Modelo 3D
```

---

## Aspectos Técnicos Avançados

### Mapeamento de Ossos
O sistema calcula direções de ossos a partir de landmarks da IA:

```dart
// Exemplo: Direção do quadril
v64.Vector3 hipUpDir = v64.Vector3(
  shoulderCenter.x - hipCenter.x,      // X: lateral
  hipCenter.y - shoulderCenter.y,      // Y: vertical (invertido)
  -(shoulderCenter.z - hipCenter.z) * _zImpact  // Z: profundidade
).normalized();
```

### Calibração por Osso
Cada osso possui offsets específicos para compensar diferenças entre a pose T do modelo e a detecção da IA:

```dart
// Exemplo: Calibração da coluna
v64.Quaternion off = 
  v64.Quaternion.axisAngle(v64.Vector3(1, 0, 0), gX * 0.0174533) *
  v64.Quaternion.axisAngle(v64.Vector3(0, 0, 1), gZ * 0.0174533) *
  v64.Quaternion.axisAngle(v64.Vector3(0, 1, 0), gY * 0.0174533);
```

### Sistema de Confiança
Filtragem de detecções com baixa confiança:

```dart
if (combinedLikelihood > _visibilityThreshold) {
  rots[boneName] = [qFinal.x, qFinal.y, qFinal.z, qFinal.w];
  lastValidRotations[boneName] = rots[boneName]!;
} else if (lastValidRotations.containsKey(boneName)) {
  rots[boneName] = lastValidRotations[boneName]!; // Usa última válida
}
```

---

## Possíveis Melhorias

### Curto Prazo

1. **Performance**
   - ✅ Implementar processamento paralelo de frames (Isolates)
   - ✅ Cache de detecções para evitar reprocessamento
   - ✅ Downscaling de vídeo antes do processamento

2. **Qualidade da Animação**
   - ✅ Suporte a SLERP (interpolação esférica) nativa
   - ✅ Sistema de IK (Inverse Kinematics) para pés e mãos
   - ✅ Detecção e aplicação de rotação da raiz (root motion)

3. **Usabilidade**
   - ✅ Preview em tempo real durante upload de vídeo
   - ✅ Edição de keyframes individuais
   - ✅ Biblioteca de poses pré-definidas

4. **Formatos**
   - ✅ Suporte para modelos FBX
   - ✅ Exportação em formatos de engine (Unity, Unreal)
   - ✅ Importação de vídeos de webcam em tempo real

### Médio Prazo

5. **Recursos Avançados**
   - ✅ Captura de expressões faciais (face landmarks)
   - ✅ Tracking de mãos e dedos (hand landmarks)
   - ✅ Multi-person tracking (múltiplos performers)

6. **IA e ML**
   - ✅ Treinamento de modelo customizado para poses específicas
   - ✅ Correção automática de poses impossíveis
   - ✅ Predição de frames faltantes

7. **Colaboração**
   - ✅ Cloud storage para projetos
   - ✅ Compartilhamento de animações
   - ✅ Marketplace de modelos e animações

### Longo Prazo

8. **Plataforma**
   - ✅ Versão web completa
   - ✅ Versão desktop (Windows, macOS, Linux)
   - ✅ Plugin para Blender/Maya

9. **Recursos Pro**
   - ✅ Captura com múltiplas câmeras
   - ✅ Integração com motion capture profissional
   - ✅ Retargeting automático entre diferentes rigs

10. **Ecossistema**
    - ✅ API para desenvolvedores
    - ✅ SDK para integração em outros apps
    - ✅ Sistema de plugins da comunidade

---

## Estatísticas do Projeto

- **Linhas de Código (Dart)**: ~850
- **Linhas de Código (JavaScript)**: ~250
- **Ossos Mapeados**: 18+
- **Landmarks Detectados**: 33
- **Taxa de Processamento**: 10 fps
- **Formatos Suportados**: GLB (entrada/saída), MP4 (entrada)

---

## Aprendizados Principais

1. **Integração Flutter-JavaScript**: Comunicação bidirecional eficiente
2. **Matemática 3D Prática**: Aplicação real de quaternions e vetores
3. **Pipeline de Processamento**: Orquestração de múltiplas tecnologias
4. **IA Aplicada**: Uso prático de modelos de visão computacional
5. **Otimização Mobile**: Balanceamento entre qualidade e performance
6. **Design de API**: Interface JavaScript clara e reutilizável

---

## Licença

Este projeto é um protótipo educacional, você pode usá-lo e modificá-lo à vontade, mas não pense em vendê-lo, pois esta é uma porta de entrada para entusiastas da Computação Gráfica que não possuem recursos avançados para seus projetos, logo, a distribuição é livre, mas a venda é proibida.

---

## Agradecimentos

- **Google ML Kit** - Pela poderosa API de detecção de poses
- **Three.js** - Pela incrível biblioteca de renderização 3D otimizada
- **Meshy.ai** - Pelo auxílio direto ao gerar modelos rigged padronizados
- **Flutter** - Pela rica documentação, compatibilidade de sistemas e portabilidade de código.

---
