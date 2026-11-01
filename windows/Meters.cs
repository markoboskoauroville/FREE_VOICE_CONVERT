// Meters.cs: the indications CPU · RAM · GPU · VRAM (Marko, 1.11.2026: "a meter is not literally a meter, it's just an
// indication"): the name and the value, a hairline under them. Read once a second, nothing installed:
//   CPU   PerformanceCounter Processor / % Processor Time / _Total
//   RAM   PerformanceCounter Memory / Available MBytes, against the installed memory
//   GPU   nvidia-smi when there is an NVIDIA card (utilization, memory free / total), else the "GPU Engine" counters
//         (3D engines, Windows 10 1709+) and "GPU Adapter Memory" dedicated usage against the adapter's memory (WMI)
using System;
using System.Diagnostics;
using System.Drawing;
using System.Linq;
using System.Management;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace FreeVoiceConvert
{
    class Hair : Control
    {
        readonly string label; readonly bool invert;
        double value; string text = "–";
        public Hair(string label, bool invert = false)
        {
            this.label = label; this.invert = invert;
            DoubleBuffered = true; Dock = DockStyle.Fill; Margin = new Padding(0, 0, 8, 0);
            AccessibleRole = AccessibleRole.Indicator; AccessibleName = label;
        }
        public void Set(double v, string t) { value = Math.Max(0, Math.Min(1, v)); text = t; AccessibleName = label + " " + t; Invalidate(); }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
            using (var bold = new Font("Consolas", 8.5f, FontStyle.Bold))
            using (var reg = new Font("Consolas", 8.5f))
            {
                g.DrawString(label, bold, Brushes.Gray, 0, 2);
                var w = g.MeasureString(label + " ", bold).Width;
                g.DrawString(text, reg, SystemBrushes.ControlText, w, 2);
            }
            double load = invert ? 1 - value : value;
            var c = load > 0.9 ? Color.Red : load > 0.7 ? Color.Orange : Color.LimeGreen;
            int y = Height - 6;
            using (var back = new Pen(Color.FromArgb(60, 128, 128, 128))) g.DrawLine(back, 0, y, Width - 1, y);
            using (var pen = new Pen(c)) g.DrawLine(pen, 0, y, Math.Max(1, (int)((Width - 1) * value)), y);
        }
    }

    class SysMeters
    {
        public double Cpu, RamFree, RamTotal, Gpu = -1, VramFree, VramTotal;
        PerformanceCounter cpu, ram;
        PerformanceCounter[] gpuEngines = new PerformanceCounter[0], gpuMem = new PerformanceCounter[0];
        readonly bool nvidia;
        bool busy;
        DateTime lastEngineScan = DateTime.MinValue;

        public SysMeters()
        {
            try { cpu = new PerformanceCounter("Processor", "% Processor Time", "_Total"); cpu.NextValue(); } catch { }
            try { ram = new PerformanceCounter("Memory", "Available MBytes"); } catch { }
            try { RamTotal = new Microsoft.VisualBasic.Devices.ComputerInfo().TotalPhysicalMemory; } catch { }
            nvidia = Run("nvidia-smi", "-L") != null;
            if (!nvidia)
            {
                try
                {
                    using (var s = new ManagementObjectSearcher("SELECT AdapterRAM FROM Win32_VideoController"))
                        foreach (var o in s.Get()) VramTotal = Math.Max(VramTotal, System.Convert.ToDouble(o["AdapterRAM"] ?? 0));
                }
                catch { }
            }
        }

        public void Read()
        {
            try { if (cpu != null) Cpu = cpu.NextValue() / 100.0; } catch { }
            try { if (ram != null) RamFree = ram.NextValue() * 1048576.0; } catch { }
            if (busy) return;
            busy = true;
            Task.Run(() =>
            {
                try { if (nvidia) ReadNvidia(); else ReadCounters(); } catch { }
                busy = false;
            });
        }

        void ReadNvidia()
        {
            var o = Run("nvidia-smi", "--query-gpu=utilization.gpu,memory.free,memory.total --format=csv,noheader,nounits");
            var f = o?.Split('\n')[0].Split(',');
            if (f == null || f.Length < 3) return;
            Gpu = double.Parse(f[0].Trim()) / 100.0;
            VramFree = double.Parse(f[1].Trim()) * 1048576.0;
            VramTotal = double.Parse(f[2].Trim()) * 1048576.0;
        }

        void ReadCounters()
        {
            if ((DateTime.Now - lastEngineScan).TotalSeconds > 10)  // processes come and go: rescan the instances
            {
                lastEngineScan = DateTime.Now;
                try
                {
                    var cat = new PerformanceCounterCategory("GPU Engine");
                    gpuEngines = cat.GetInstanceNames().Where(n => n.Contains("engtype_3D"))
                        .Select(n => new PerformanceCounter("GPU Engine", "Utilization Percentage", n)).ToArray();
                    foreach (var c in gpuEngines) c.NextValue();
                    var mem = new PerformanceCounterCategory("GPU Adapter Memory");
                    gpuMem = mem.GetInstanceNames().Select(n => new PerformanceCounter("GPU Adapter Memory", "Dedicated Usage", n)).ToArray();
                }
                catch { gpuEngines = new PerformanceCounter[0]; }
                return;
            }
            double u = 0;
            foreach (var c in gpuEngines) { try { u += c.NextValue(); } catch { } }
            Gpu = Math.Min(1, u / 100.0);
            double used = 0;
            foreach (var c in gpuMem) { try { used = Math.Max(used, c.NextValue()); } catch { } }
            if (VramTotal > 0) VramFree = Math.Max(0, VramTotal - used);
        }

        static string Run(string exe, string args)
        {
            try
            {
                var p = Process.Start(new ProcessStartInfo(exe, args) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true });
                var o = p.StandardOutput.ReadToEnd();
                p.WaitForExit(3000);
                return p.ExitCode == 0 ? o : null;
            }
            catch { return null; }
        }
    }
}
