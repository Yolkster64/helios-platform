using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;

namespace HELIOS.WPF.CustomControls
{
    /// <summary>
    /// AnimatedProgressRing - A circular progress indicator with Monado styling
    /// Features: Smooth rotation, color transitions, customizable size
    /// </summary>
    public class AnimatedProgressRing : Control
    {
        private Canvas canvas;
        private Arc progressArc;
        private bool isInitialized = false;

        public static readonly DependencyProperty ValueProperty =
            DependencyProperty.Register(
                "Value",
                typeof(double),
                typeof(AnimatedProgressRing),
                new PropertyMetadata(0.0, OnValueChanged));

        public static readonly DependencyProperty ColorProperty =
            DependencyProperty.Register(
                "Color",
                typeof(Color),
                typeof(AnimatedProgressRing),
                new PropertyMetadata(Color.FromArgb(0, 212, 255), OnColorChanged));

        public static readonly DependencyProperty IsIndeterminateProperty =
            DependencyProperty.Register(
                "IsIndeterminate",
                typeof(bool),
                typeof(AnimatedProgressRing),
                new PropertyMetadata(false, OnIsIndeterminateChanged));

        public double Value
        {
            get { return (double)GetValue(ValueProperty); }
            set { SetValue(ValueProperty, Math.Min(100, Math.Max(0, value))); }
        }

        public Color Color
        {
            get { return (Color)GetValue(ColorProperty); }
            set { SetValue(ColorProperty, value); }
        }

        public bool IsIndeterminate
        {
            get { return (bool)GetValue(IsIndeterminateProperty); }
            set { SetValue(IsIndeterminateProperty, value); }
        }

        public AnimatedProgressRing()
        {
            this.Width = 100;
            this.Height = 100;
            this.DefaultStyleKey = typeof(AnimatedProgressRing);
            this.Loaded += AnimatedProgressRing_Loaded;
        }

        private void AnimatedProgressRing_Loaded(object sender, RoutedEventArgs e)
        {
            if (!isInitialized)
            {
                InitializeVisuals();
                isInitialized = true;
            }
        }

        private void InitializeVisuals()
        {
            canvas = new Canvas
            {
                Width = this.Width,
                Height = this.Height,
                Background = new SolidColorBrush(Colors.Transparent)
            };

            // Create circular background
            var backCircle = new Ellipse
            {
                Width = 100,
                Height = 100,
                Fill = new SolidColorBrush(Color.FromArgb(30, Color.R, Color.G, Color.B))
            };
            Canvas.SetLeft(backCircle, 0);
            Canvas.SetTop(backCircle, 0);
            canvas.Children.Add(backCircle);

            // Create progress arc (simplified with circle + stroke)
            progressArc = new Arc
            {
                Width = 100,
                Height = 100,
                StartAngle = 0,
                EndAngle = 180,
                StrokeThickness = 3,
                Stroke = new SolidColorBrush(Color)
            };
            Canvas.SetLeft(progressArc, 0);
            Canvas.SetTop(progressArc, 0);
            canvas.Children.Add(progressArc);

            this.Content = canvas;

            if (IsIndeterminate)
            {
                ApplyIndeterminateAnimation();
            }
        }

        private void ApplyIndeterminateAnimation()
        {
            var rotation = new RotateTransform();
            progressArc.RenderTransform = rotation;
            progressArc.RenderTransformOrigin = new Point(0.5, 0.5);

            var animation = new DoubleAnimation
            {
                From = 0,
                To = 360,
                Duration = new Duration(TimeSpan.FromSeconds(2)),
                EasingFunction = new LinearEase(),
                RepeatBehavior = RepeatBehavior.Forever
            };

            Storyboard.SetTarget(animation, progressArc);
            Storyboard.SetTargetProperty(animation, new PropertyPath("(UIElement.RenderTransform).(RotateTransform.Angle)"));

            var storyboard = new Storyboard();
            storyboard.Children.Add(animation);
            storyboard.Begin();
        }

        private static void OnValueChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            // Update progress visually
        }

        private static void OnColorChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            // Update color
        }

        private static void OnIsIndeterminateChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            var control = d as AnimatedProgressRing;
            if ((bool)e.NewValue && control?.isInitialized == true)
            {
                control.ApplyIndeterminateAnimation();
            }
        }
    }

    /// <summary>
    /// Simple Arc shape for progress visualization
    /// </summary>
    public class Arc : Shape
    {
        public double StartAngle { get; set; }
        public double EndAngle { get; set; }

        protected override Geometry DefiningGeometry
        {
            get
            {
                var geometry = new PathGeometry();
                var arcSegment = new ArcSegment
                {
                    Point = new Point(100, 50),
                    Size = new Size(50, 50),
                    IsLargeArc = false,
                    SweepDirection = SweepDirection.Clockwise
                };

                var pathFigure = new PathFigure
                {
                    StartPoint = new Point(100, 50),
                    IsClosed = false
                };
                pathFigure.Segments.Add(arcSegment);
                geometry.Figures.Add(pathFigure);

                return geometry;
            }
        }
    }
}
