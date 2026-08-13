using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;

namespace HELIOS.WPF.CustomControls
{
    /// <summary>
    /// MonadoGlowBorder - A custom border with Monado cyan glow effect
    /// Features: Radial gradient glow, smooth animations, adjustable intensity
    /// </summary>
    public class MonadoGlowBorder : Border
    {
        private Ellipse glowEllipse;
        private bool isInitialized = false;

        public static readonly DependencyProperty GlowColorProperty =
            DependencyProperty.Register(
                "GlowColor",
                typeof(Color),
                typeof(MonadoGlowBorder),
                new PropertyMetadata(Color.FromArgb(0, 0, 212, 255), OnGlowColorChanged));

        public static readonly DependencyProperty GlowIntensityProperty =
            DependencyProperty.Register(
                "GlowIntensity",
                typeof(double),
                typeof(MonadoGlowBorder),
                new PropertyMetadata(0.6, OnGlowIntensityChanged));

        public static readonly DependencyProperty EnablePulseProperty =
            DependencyProperty.Register(
                "EnablePulse",
                typeof(bool),
                typeof(MonadoGlowBorder),
                new PropertyMetadata(true, OnEnablePulseChanged));

        public Color GlowColor
        {
            get { return (Color)GetValue(GlowColorProperty); }
            set { SetValue(GlowColorProperty, value); }
        }

        public double GlowIntensity
        {
            get { return (double)GetValue(GlowIntensityProperty); }
            set { SetValue(GlowIntensityProperty, value); }
        }

        public bool EnablePulse
        {
            get { return (bool)GetValue(EnablePulseProperty); }
            set { SetValue(EnablePulseProperty, value); }
        }

        public MonadoGlowBorder()
        {
            this.Loaded += MonadoGlowBorder_Loaded;
        }

        private void MonadoGlowBorder_Loaded(object sender, RoutedEventArgs e)
        {
            if (!isInitialized)
            {
                InitializeGlow();
                isInitialized = true;
            }
        }

        private void InitializeGlow()
        {
            glowEllipse = new Ellipse
            {
                Fill = new RadialGradientBrush
                {
                    GradientStops = new GradientStopCollection
                    {
                        new GradientStop(Color.FromArgb((byte)(GlowIntensity * 200), GlowColor.R, GlowColor.G, GlowColor.B), 0),
                        new GradientStop(Color.FromArgb((byte)(GlowIntensity * 100), GlowColor.R, GlowColor.G, GlowColor.B), 0.5),
                        new GradientStop(Color.FromArgb(0, GlowColor.R, GlowColor.G, GlowColor.B), 1)
                    }
                }
            };

            // Position glow behind border
            var panel = new Grid();
            panel.Children.Add(glowEllipse);
            panel.Children.Add(new Border
            {
                Background = this.Background,
                BorderBrush = this.BorderBrush,
                BorderThickness = this.BorderThickness,
                CornerRadius = this.CornerRadius,
                Child = this.Child,
                Padding = this.Padding
            });

            this.Background = new SolidColorBrush(Colors.Transparent);
            this.Child = panel;

            if (EnablePulse)
            {
                ApplyPulseAnimation();
            }
        }

        private void ApplyPulseAnimation()
        {
            if (glowEllipse == null) return;

            var animation = new DoubleAnimation
            {
                From = GlowIntensity * 0.5,
                To = GlowIntensity,
                Duration = new Duration(TimeSpan.FromMilliseconds(666)),
                EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut },
                AutoReverse = true,
                RepeatBehavior = RepeatBehavior.Forever
            };

            Storyboard.SetTarget(animation, glowEllipse);
            Storyboard.SetTargetProperty(animation, new PropertyPath("Opacity"));

            var storyboard = new Storyboard();
            storyboard.Children.Add(animation);
            storyboard.Begin();
        }

        private static void OnGlowColorChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            var control = d as MonadoGlowBorder;
            if (control?.glowEllipse != null)
            {
                var color = (Color)e.NewValue;
                control.glowEllipse.Fill = new RadialGradientBrush
                {
                    GradientStops = new GradientStopCollection
                    {
                        new GradientStop(Color.FromArgb((byte)(control.GlowIntensity * 200), color.R, color.G, color.B), 0),
                        new GradientStop(Color.FromArgb((byte)(control.GlowIntensity * 100), color.R, color.G, color.B), 0.5),
                        new GradientStop(Color.FromArgb(0, color.R, color.G, color.B), 1)
                    }
                };
            }
        }

        private static void OnGlowIntensityChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            // Update glow
        }

        private static void OnEnablePulseChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            var control = d as MonadoGlowBorder;
            if ((bool)e.NewValue)
            {
                control?.ApplyPulseAnimation();
            }
        }
    }
}
