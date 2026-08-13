---
name: winui3-shell
description: WinUI 3 desktop shell for HELIOS — Windows App SDK setup, CommunityToolkit MVVM, x:Bind, DispatcherQueue threading, Win2D rendering, theming, and the AIHubWindow provider-dashboard revival. Use when building or reviewing GUI code for the HELIOS shell (successor to the orphaned WPF MonadoBlade.GUI).
---

Hub-and-spoke rule: the WinUI 3 shell is part of the C# orchestrator CENTER — it binds to hub libraries (HELIOS.AIHub etc.) in-process and reaches native spokes only through the hub's interop layer, never by loading spoke DLLs itself.

## Project setup: Windows App SDK

Target `net8.0-windows10.0.19041.0` (repo is net8.0 today; .NET 10 is the current LTS to migrate toward — .NET 11 is preview, ships Nov 2026, do not target it). Reference `Microsoft.WindowsAppSDK` + `Microsoft.Windows.SDK.BuildTools`.

- Unpackaged (`<WindowsPackageType>None</WindowsPackageType>` + `<WindowsAppSDKSelfContained>true</WindowsAppSDKSelfContained>`): xcopy deploy, easiest for dev loops and the current HELIOS distribution model.
- MSIX: identity, clean install/uninstall, store/enterprise deployment, required for some APIs (share targets, certain background tasks). Start unpackaged; add MSIX packaging as a second head when distribution demands it.

## MVVM with CommunityToolkit.Mvvm

Source generators kill the boilerplate — partial class + attributes:

```csharp
public partial class ProviderViewModel : ObservableObject
{
    [ObservableProperty]
    private double _latencyMs;                 // generates LatencyMs + change notification

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(RefreshCommand))]
    private bool _isOnline;

    [RelayCommand(CanExecute = nameof(IsOnline))]
    private async Task RefreshAsync(CancellationToken ct)
        => Metrics = await _hub.GetMetricsAsync(ProviderId, ct);
}
```

ViewModels reference `HELIOS.AIHub` service interfaces via constructor injection (`Microsoft.Extensions.DependencyInjection` in `App.xaml.cs`); no service-locator lookups in code-behind.

## x:Bind over Binding

`{x:Bind}` is compiled: type-checked at build, no reflection, faster startup. Default is `OneTime` — say `Mode=OneWay` explicitly for live values:

```xml
<TextBlock Text="{x:Bind ViewModel.LatencyMs, Mode=OneWay}" />
<Button Command="{x:Bind ViewModel.RefreshCommand}" Content="Refresh" />
```

Use classic `{Binding}` only where x:Bind cannot go (dynamic DataContext scenarios, some ControlTemplate cases). Pages expose `ViewModel` as a get-only property so x:Bind has a typed root.

## Threading: DispatcherQueue

UI objects are single-threaded. Worker threads and hub event callbacks must enqueue:

```csharp
private readonly DispatcherQueue _dq = DispatcherQueue.GetForCurrentThread(); // capture on UI thread

void OnMetricsUpdated(ProviderMetrics m) =>
    _dq.TryEnqueue(() => ViewModel.Apply(m));   // never touch bound properties off-thread
```

`GetForCurrentThread()` returns null on non-UI threads — capture the queue at construction, don't fetch it in the callback. `async/await` continuations after UI-thread awaits are already on the UI thread; the enqueue rule is for events originating on hub/background threads.

## Composition and animation

Implicit animations make metric changes feel alive without a frame loop:

```csharp
var visual = ElementCompositionPreview.GetElementVisual(Card);
var comp = visual.Compositor;
var anim = comp.CreateVector3KeyFrameAnimation();
anim.InsertKeyFrame(1f, new Vector3(1.03f, 1.03f, 1f));
anim.Duration = TimeSpan.FromMilliseconds(120);
visual.Scale = Vector3.One;                     // animate on hover via anim
```

Prefer built-in `AnimatedIcon`/`ThemeShadow` and Composition over per-frame CPU redraws; the compositor runs off the UI thread.

## Win2D for custom rendering

Latency sparklines and cost charts: `CanvasControl` with a `Draw` handler is enough.

```csharp
void OnDraw(CanvasControl sender, CanvasDrawEventArgs args)
{
    using var path = BuildSparkline(sender.Size, _samples);
    args.DrawingSession.DrawGeometry(path, Colors.SteelBlue, 2f);
}
```

Use `CanvasVirtualControl` for large scrollable surfaces. For heavy scenes (thousands of animated elements, custom shaders) the escape hatch is the C++ spoke: a C++/WinRT component sharing the Win2D/D3D device (`ICanvasDevice` interop) — the shell consumes its runtime class; it does not write D3D in C#.

## Theming

Light/Dark/HighContrast come from resource dictionaries; brushes must use `ThemeResource` so they re-resolve on theme change — `StaticResource` freezes the launch theme:

```xml
<Border Background="{ThemeResource CardBackgroundFillColorDefaultBrush}">
```

Override per-theme in `App.xaml`:

```xml
<ResourceDictionary.ThemeDictionaries>
    <ResourceDictionary x:Key="Light"><SolidColorBrush x:Key="AccentBrush" Color="#0B6BCB"/></ResourceDictionary>
    <ResourceDictionary x:Key="Dark"><SolidColorBrush x:Key="AccentBrush" Color="#5AB0FF"/></ResourceDictionary>
    <ResourceDictionary x:Key="HighContrast"><SolidColorBrush x:Key="AccentBrush" Color="{ThemeResource SystemColorHighlightColor}"/></ResourceDictionary>
</ResourceDictionary.ThemeDictionaries>
```

Always provide the HighContrast entry; test with a contrast theme enabled before shipping a page.

## Windowing: AppWindow

`Window` wraps an `AppWindow`; use it for titlebar, size, presenters:

```csharp
var appWindow = this.AppWindow;                       // WinUI 3 exposes it directly
appWindow.Resize(new SizeInt32(1280, 800));
appWindow.SetIcon("Assets/helios.ico");
appWindow.TitleBar.ExtendsContentIntoTitleBar = true; // custom titlebar w/ drag regions
```

Secondary tool windows (like AIHubWindow) are separate `Window` instances — each has its own DispatcherQueue; never share UI objects between them.

## AIHubWindow revival

The orphaned WPF MonadoBlade.GUI provider dashboard returns as a WinUI 3 page: an `ItemsRepeater`/`ListView` of provider cards (anthropic, openai+codex, copilot, azure-foundry, ollama from `config/aihub.json`) bound to `HELIOS.AIHub`:

```csharp
[ObservableProperty] private ObservableCollection<ProviderCardViewModel> _providers = [];

private async Task LoadAsync(CancellationToken ct)
{
    var status = await _hub.GetStatusAsync(ct);       // online/offline, active model
    var metrics = await _hub.GetMetricsAsync(ct);     // latency p50/p95, cost, success rate
    foreach (var p in status.Providers)
        Providers.Add(new ProviderCardViewModel(p, metrics[p.Id]));
}
```

Each card: status dot (ThemeResource brush), latency + success-rate text via x:Bind OneWay, Win2D sparkline for recent latency, per-1k-token cost from the hub's pricing data. Poll or subscribe via the hub only — the shell never calls provider endpoints itself.

## Which LLM to use (via helios-ai / aihub.json)

| Task | Provider | Why |
|---|---|---|
| XAML layout decisions, MVVM structure, navigation design | anthropic (Claude) or openai (GPT) | Structural reasoning across views/VMs |
| XAML boilerplate: styles, templates, converter stubs | openai+codex | Mechanical markup generation |
| Property/snippet completion in code-behind and VMs | copilot | Inline completion |

## Reference material

- `references/xaml-authoring.md` — deep XAML authoring: x:Bind vs Binding traps, DataTemplates and list-control choice, ThemeResource lifetime, VisualStateManager, Hot Reload limits, XamlStyler/WinUI 3 Gallery, and the contract for requesting XAML from the hub's LLM agents.
- `references/rendering-interop.md` — the C#↔C++ rendering seam: Win2D control choice, SwapChainPanel/ISwapChainPanelNative interop, Microsoft.UI.Composition, DispatcherQueue rules for render loops, the managed-vs-native-spoke decision, and frame-pacing/vsync pitfalls.
- `references/interaction-and-motion.md` — Composition implicit/spring/expression patterns (pointer-parallax expression), custom radial-control input (PointerWheelChanged, keyboard parity, AutomationPeer), reduced-motion detection, hit-test transparency layering, and WPF→WinUI porting notes for the recovered docs/ui-xenoblade seeds.
