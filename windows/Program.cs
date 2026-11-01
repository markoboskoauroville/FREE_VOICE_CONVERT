// Free Voice Convert Equalizer for Windows: the same window as the Mac app, driving the same engine (engine\fvc.py).
// Python, Seed-VC and the models live in %LOCALAPPDATA%\FreeVoiceConvert, installed by engine\setup.ps1 (the
// installer runs it; this window runs it again when anything is missing).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace FreeVoiceConvert
{
    static class Program
    {
        public const int VERSION = 4;
        public const string SITE = "https://freevoiceconvert.pages.dev";

        [STAThread]
        static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
        }
    }

    class Profile { public string id, name, source, dir; public override string ToString() => name; }

    class MainForm : Form
    {
        static readonly string Home = Environment.GetEnvironmentVariable("FVC_HOME") ??
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FreeVoiceConvert");
        static readonly string Python = Path.Combine(Home, "venv", "Scripts", "python.exe");
        static readonly string EngineDir = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "engine");
        static readonly string Fvc = Path.Combine(EngineDir, "fvc.py");
        static readonly string Settings = Path.Combine(Home, "window.json");
        readonly JavaScriptSerializer json = new JavaScriptSerializer();

        readonly Button btnVoice = new Button { Text = "SOURCE VOICE…", AutoSize = true };
        readonly ComboBox cmbProfile = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 260 };
        readonly Button btnAdd = new Button { Text = "ADD FILES…", AutoSize = true };
        readonly Button btnUp = new Button { Text = "▲", Width = 32 };
        readonly Button btnDown = new Button { Text = "▼", Width = 32 };
        readonly Button btnRemove = new Button { Text = "REMOVE", AutoSize = true };
        readonly Button btnClear = new Button { Text = "CLEAR", AutoSize = true };
        readonly ListBox lstClips = new ListBox { Dock = DockStyle.Fill, SelectionMode = SelectionMode.MultiExtended, AllowDrop = true, IntegralHeight = false };
        readonly RadioButton rConvert = new RadioButton { Text = "CONVERT", AutoSize = true, Checked = true };
        readonly RadioButton rKeep = new RadioButton { Text = "KEEP", AutoSize = true };
        readonly RadioButton rSpeech = new RadioButton { Text = "SPEECH (22 kHz, safest)", AutoSize = true, Checked = true };
        readonly RadioButton rStudio = new RadioButton { Text = "STUDIO (44.1 kHz, melody kept)", AutoSize = true };
        readonly RadioButton rOne = new RadioButton { Text = "ONE BY ONE", AutoSize = true, Checked = true };
        readonly RadioButton rStitch = new RadioButton { Text = "STITCHED", AutoSize = true };
        readonly RadioButton rBoth = new RadioButton { Text = "BOTH", AutoSize = true };
        readonly CheckBox chkClean = new CheckBox { Text = "CLEAN the input first", AutoSize = true, Checked = true };
        readonly CheckBox chkTop = new CheckBox { Text = "TOP", AutoSize = true };
        readonly Button btnGo = new Button { Text = "CONVERT", Width = 110, Height = 32 };
        readonly Button btnInstall = new Button { Text = "INSTALL", AutoSize = true };
        readonly Button btnShow = new Button { Text = "SHOW", AutoSize = true, Visible = false };
        readonly ProgressBar bar = new ProgressBar { Dock = DockStyle.Fill, Maximum = 1000 };
        readonly Label lblMsg = new Label { AutoSize = false, Dock = DockStyle.Fill, Text = "checking the engine", TextAlign = ContentAlignment.MiddleLeft };
        readonly TextBox txtLog = new TextBox { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill, Font = new Font("Consolas", 8f) };
        readonly LinkLabel lnkVersion = new LinkLabel { Text = "v" + Program.VERSION, AutoSize = true };
        // one line of times (Marko, 1.11.2026): done / total · countdown · the clock time it ends · running time and fps
        // beside ③: the percentage while it runs; after a STOP "CONVERTED 50 %", and CONVERT goes on from there
        readonly Label lblPct = new Label { AutoSize = true, Font = new Font("Consolas", 10.5f, FontStyle.Bold), ForeColor = Color.ForestGreen, Padding = new Padding(0, 7, 10, 0) };
        readonly Hair hDone = new Hair("CONVERTED"), hLeft = new Hair("TIME LEFT"), hEnds = new Hair("ENDS AT"), hRun = new Hair("RUNNING"), hFps = new Hair("SPEED");
        readonly Hair hCpu = new Hair("CPU", true), hRam = new Hair("RAM FREE", true, true), hGpu = new Hair("GPU", true), hVram = new Hair("VRAM FREE", true, true);
        readonly SysMeters meters = new SysMeters();
        readonly Timer tick = new Timer { Interval = 1000 };
        double totalS, doneS, startedS, fps = 25;
        DateTime? startedAt;
        bool autoResumed;

        List<Profile> profiles = new List<Profile>();
        List<string> outputs = new List<string>();
        Process proc;
        bool ready;

        public MainForm()
        {
            Text = "Free Voice Convert Equalizer";
            MinimumSize = new Size(520, 560);
            Size = new Size(560, 640);
            Font = new Font("Segoe UI", 9.5f);
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

            var root = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, Padding = new Padding(12) };
            Controls.Add(root);

            // the window is a workflow, three steps top to bottom (Marko, 1.11.2026)
            var top = Row();
            top.Controls.Add(new Label { Text = "FREE VOICE CONVERT", AutoSize = true, Font = new Font("Consolas", 10f, FontStyle.Bold), Padding = new Padding(0, 6, 8, 0) });
            top.Controls.Add(chkTop); top.Controls.Add(lnkVersion); top.Controls.Add(btnInstall);
            root.Controls.Add(top);
            root.Controls.Add(Line());

            var s1 = Row();
            s1.Controls.Add(step1); s1.Controls.Add(Pipe()); s1.Controls.Add(newTask);
            root.Controls.Add(s1);
            root.Controls.Add(lstClips);
            root.Controls.Add(Line());

            var s2 = Row();
            s2.Controls.Add(Step("②  HOW TO EXPORT")); s2.Controls.Add(rOne); s2.Controls.Add(Pipe()); s2.Controls.Add(rStitch); s2.Controls.Add(Pipe()); s2.Controls.Add(rBoth);
            root.Controls.Add(s2);
            root.Controls.Add(Line());

            var s3 = new TableLayoutPanel { Dock = DockStyle.Top, ColumnCount = 3, Height = 38 };
            s3.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize)); s3.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize)); s3.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            s3.Controls.Add(step3, 0, 0); s3.Controls.Add(lblPct, 1, 0); s3.Controls.Add(bar, 2, 0);
            root.Controls.Add(s3);
            root.Controls.Add(lblMsg);
            // one table: the times on the first row, the machine on the second (Marko, 1.11.2026: "Make a table layout")
            var table = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 5, RowCount = 2 };
            for (int i = 0; i < 5; i++) table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 20));
            table.RowStyles.Add(new RowStyle(SizeType.Absolute, 38)); table.RowStyles.Add(new RowStyle(SizeType.Absolute, 38));
            table.Controls.Add(hDone, 0, 0); table.Controls.Add(hLeft, 1, 0); table.Controls.Add(hEnds, 2, 0); table.Controls.Add(hRun, 3, 0); table.Controls.Add(hFps, 4, 0);
            table.Controls.Add(hCpu, 0, 1); table.Controls.Add(hRam, 1, 1); table.Controls.Add(hGpu, 2, 1); table.Controls.Add(hVram, 3, 1);
            root.Controls.Add(table);
            root.Controls.Add(txtLog);
            txtLog.Visible = false;  // the installation shows it; a conversion does not
            // rows: top, line, ① title, the files (all the extra height), line, ②, line, ③, message, table, log
            foreach (var st in new[] {
                new RowStyle(SizeType.AutoSize), new RowStyle(SizeType.Absolute, 9), new RowStyle(SizeType.AutoSize),
                new RowStyle(SizeType.Percent, 100), new RowStyle(SizeType.Absolute, 9), new RowStyle(SizeType.AutoSize),
                new RowStyle(SizeType.Absolute, 9), new RowStyle(SizeType.Absolute, 44), new RowStyle(SizeType.Absolute, 26),
                new RowStyle(SizeType.Absolute, 82), new RowStyle(SizeType.AutoSize) }) root.RowStyles.Add(st);
            tick.Tick += (s, e) => { UpdateStats(); meters.Read(); hCpu.Set(meters.Cpu, $"{meters.Cpu * 100:0}%");
                hRam.Set(meters.RamTotal > 0 ? meters.RamFree / meters.RamTotal : 0, Gb(meters.RamFree));
                hGpu.Set(meters.Gpu, meters.Gpu < 0 ? "–" : $"{meters.Gpu * 100:0}%");
                hVram.Set(meters.VramTotal > 0 ? meters.VramFree / meters.VramTotal : 0, meters.VramTotal > 0 ? Gb(meters.VramFree) : "–"); };
            tick.Start();

            step1.Click += (s, e) => PickClips();
            newTask.Click += (s, e) =>
            {
                if (proc != null) return;
                lstClips.Items.Clear(); outputs.Clear(); bar.Value = 0; lblMsg.Text = "ready";
                totalS = doneS = startedS = 0; startedAt = null; UpdateStats(); Busy(false);
            };
            step3.Click += (s, e) => { if (proc != null) Stop(); else if (ready) Convert(); };
            // the list without buttons: Delete removes, Alt+Up/Down moves, the right click offers the same
            lstClips.KeyDown += (s, e) =>
            {
                if (e.KeyCode == Keys.Delete) btnRemove.PerformClick();
                else if (e.Alt && e.KeyCode == Keys.Up) { Move(-1); e.Handled = true; }
                else if (e.Alt && e.KeyCode == Keys.Down) { Move(1); e.Handled = true; }
            };
            var menu = new ContextMenuStrip();
            menu.Items.Add("Move up", null, (s, e) => Move(-1));
            menu.Items.Add("Move down", null, (s, e) => Move(1));
            menu.Items.Add("Remove", null, (s, e) => btnRemove.PerformClick());
            menu.Items.Add("Remove all", null, (s, e) => lstClips.Items.Clear());
            lstClips.ContextMenuStrip = menu;
            btnVoice.Click += (s, e) => PickVoice();
            btnAdd.Click += (s, e) => PickClips();
            btnClear.Click += (s, e) => lstClips.Items.Clear();
            btnRemove.Click += (s, e) => { foreach (var i in lstClips.SelectedIndices.Cast<int>().OrderByDescending(x => x).ToList()) lstClips.Items.RemoveAt(i); };
            btnUp.Click += (s, e) => Move(-1);
            btnDown.Click += (s, e) => Move(1);
            btnGo.Click += (s, e) => { if (proc != null) Stop(); else Convert(); };
            btnInstall.Click += (s, e) => Install();
            btnShow.Click += (s, e) => { if (outputs.Count > 0) Process.Start("explorer.exe", "/select,\"" + outputs[0] + "\""); };
            chkTop.CheckedChanged += (s, e) => { TopMost = chkTop.Checked; SaveSettings(); };
            lnkVersion.LinkClicked += (s, e) => Process.Start(Program.SITE);
            lstClips.DragEnter += (s, e) => e.Effect = e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
            lstClips.DragDrop += (s, e) => { foreach (var f in (string[])e.Data.GetData(DataFormats.FileDrop)) lstClips.Items.Add(f); };
            AllowDrop = true;
            DragEnter += (s, e) => e.Effect = DragDropEffects.Copy;
            DragDrop += (s, e) => { foreach (var f in (string[])e.Data.GetData(DataFormats.FileDrop)) lstClips.Items.Add(f); };
            FormClosing += (s, e) => { SaveSettings(); Stop(); };
            StartPosition = FormStartPosition.Manual;
            Shown += (s, e) => { LoadSettings(); Check(); };
        }

        // the round number is the button (Marko, 1.11.2026): lit on hover, a click does the step
        readonly Label step1 = StepButton("①  ADD FILES");
        readonly Label step3 = StepButton("③  CONVERT");
        // a clean start: the list and the numbers emptied (Marko, 1.11.2026)
        readonly Label newTask = StepButton("NEW TASK");

        static Label StepButton(string t)
        {
            var l = new Label { Text = t, AutoSize = true, Font = new Font("Consolas", 11f, FontStyle.Bold), ForeColor = Color.ForestGreen, Padding = new Padding(0, 6, 10, 0), Cursor = Cursors.Hand };
            l.MouseEnter += (s, e) => { if (l.Enabled) { l.ForeColor = Color.LimeGreen; l.Font = new Font("Consolas", 11f, FontStyle.Bold | FontStyle.Underline); } };
            l.MouseLeave += (s, e) => { l.ForeColor = Color.ForestGreen; l.Font = new Font("Consolas", 11f, FontStyle.Bold); };
            l.AccessibleRole = AccessibleRole.PushButton;
            l.AccessibleName = t.TrimStart('①', '②', '③', ' ');
            return l;
        }

        static Label Step(string t) => new Label { Text = t, AutoSize = true, Font = new Font("Consolas", 10.5f, FontStyle.Bold), ForeColor = Color.ForestGreen, Padding = new Padding(0, 7, 10, 0) };

        // choices on one line are parted by pipes (Marko, 1.11.2026)
        // a thin grey line across the window between the parts (Marko, 1.11.2026, as in his Network Aggregate window)
        static Control Line() => new Panel { Height = 1, Dock = DockStyle.Top, BackColor = Color.FromArgb(90, 128, 128, 128), Margin = new Padding(0, 4, 0, 4) };

        static Label Pipe() => new Label { Text = "|", AutoSize = true, ForeColor = Color.Gray, Font = new Font("Consolas", 10.5f, FontStyle.Bold), Padding = new Padding(0, 4, 0, 0) };

        static FlowLayoutPanel Row() => new FlowLayoutPanel { Dock = DockStyle.Top, AutoSize = true, WrapContents = true };

        static Control Group(string title, params Control[] cs)
        {
            var p = Row();
            p.Controls.Add(new Label { Text = title, Width = 70, Font = new Font("Segoe UI", 9f, FontStyle.Bold), Padding = new Padding(0, 5, 0, 0) });
            var inner = new FlowLayoutPanel { AutoSize = true, WrapContents = true };
            foreach (var c in cs) inner.Controls.Add(c);
            p.Controls.Add(inner);
            return p;
        }

        void Move(int d)
        {
            int i = lstClips.SelectedIndex, j = i + d;
            if (i < 0 || j < 0 || j >= lstClips.Items.Count) return;
            var it = lstClips.Items[i]; lstClips.Items.RemoveAt(i); lstClips.Items.Insert(j, it);
            lstClips.ClearSelected(); lstClips.SelectedIndex = j;
        }

        // ---------------------------------------------------------------- the engine
        // job: the conversion or the installation, which STOP / RESUME follow; a helper run (check, profile) never
        // touches proc or the busy state (a check ending during a job used to lose the job, 1.11.2026)
        void Run(string exe, string args, Action<int> done, bool job = true)
        {
            var psi = new ProcessStartInfo(exe, args)
            {
                UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8,
            };
            psi.EnvironmentVariables["FVC_HOME"] = Home;
            psi.EnvironmentVariables["PYTHONUNBUFFERED"] = "1";
            psi.EnvironmentVariables["PYTHONIOENCODING"] = "utf-8";
            var p = new Process { StartInfo = psi, EnableRaisingEvents = true };
            p.OutputDataReceived += (s, e) => { if (e.Data != null) BeginInvoke(new Action(() => Line(e.Data))); };
            p.ErrorDataReceived += (s, e) => { if (e.Data != null) BeginInvoke(new Action(() => Line(e.Data))); };
            p.Exited += (s, e) => BeginInvoke(new Action(() => { int c = p.ExitCode; if (job && proc == p) { proc = null; Busy(false); } done(c); }));
            try { p.Start(); p.BeginOutputReadLine(); p.BeginErrorReadLine(); if (job) { proc = p; Busy(true); } }
            catch (Exception ex) { lblMsg.Text = "could not start: " + ex.Message; lblMsg.ForeColor = Color.Firebrick; }
        }

        void Py(string args, Action<int> done, bool job = true) => Run(Python, Q(Fvc) + " " + args, done, job);
        static string Q(string s) => "\"" + s.Replace("\"", "\\\"") + "\"";

        void Line(string s)
        {
            var t = s.Trim();
            if (t.Length == 0) return;
            if (t.StartsWith("@"))
            {
                try
                {
                    var j = json.Deserialize<Dictionary<string, object>>(t.Substring(1));
                    if (j.TryGetValue("pct", out var p)) bar.Value = Math.Max(0, Math.Min(1000, (int)(System.Convert.ToDouble(p) * 10)));
                    if (j.TryGetValue("msg", out var m)) { lblMsg.Text = m.ToString(); lblMsg.ForeColor = SystemColors.ControlText; }
                    if (j.TryGetValue("error", out var er)) { lblMsg.Text = er.ToString(); lblMsg.ForeColor = Color.Firebrick; }
                    if (j.TryGetValue("total_s", out var ts)) totalS = System.Convert.ToDouble(ts);
                    if (j.TryGetValue("fps", out var fp)) fps = System.Convert.ToDouble(fp);
                    if (j.TryGetValue("done_s", out var ds))
                    {
                        doneS = System.Convert.ToDouble(ds);
                        // the clock starts at the first clip really converted (clips done before a STOP are only read back)
                        if (startedAt == null && j.ContainsKey("clip") && !j.ContainsKey("cached")) { startedAt = DateTime.Now; startedS = doneS; }
                    }
                    if (j.TryGetValue("outputs", out var o) && o is System.Collections.ArrayList a && a.Count > 0)
                    { outputs = a.Cast<object>().Select(x => x.ToString()).ToList(); btnShow.Visible = true; }
                    return;
                }
                catch { }
            }
            txtLog.AppendText(t + Environment.NewLine);
        }

        void Busy(bool b)
        {
            btnGo.Text = b ? "STOP" : "CONVERT";
            // one button: CONVERT, STOP while it runs, RESUME after a STOP (Marko, 1.11.2026)
            step3.Text = b ? "③  STOP" : (totalS > 0 && doneS > 0 && outputs.Count == 0 ? "③  RESUME" : "③  CONVERT");
            btnInstall.Enabled = !b; btnVoice.Enabled = !b && ready;
        }

        void Stop() { try { if (proc != null && !proc.HasExited) KillTree(proc.Id); } catch { } }
        static void KillTree(int pid) { try { Process.Start(new ProcessStartInfo("taskkill", "/T /F /PID " + pid) { CreateNoWindow = true, UseShellExecute = false }); } catch { } }

        void Check()
        {
            // not complete: the installation goes on by itself from where it stopped (once per start; nothing is
            // downloaded twice: curl -C -, uv's cache, Hugging Face's partial files)
            if (!File.Exists(Python)) { SetReady(false, "installing"); Resume(); return; }
            if (proc != null) return;  // a job is running: everything is here
            Py("check", c => { SetReady(c == 0, c == 0 ? "ready" : "some parts are missing"); if (c == 0) LoadProfiles(); else Resume(); }, false);
        }

        void Resume()
        {
            if (autoResumed) { lblMsg.Text = "the installation stopped (see the log); press INSTALL to go on"; return; }
            autoResumed = true;
            Install();
        }

        void SetReady(bool r, string msg)
        {
            ready = r; lblMsg.Text = msg;
            btnInstall.Visible = !r; btnVoice.Enabled = r; btnGo.Enabled = r;
        }

        void Install()
        {
            txtLog.Clear(); txtLog.Visible = true; bar.Value = 0; lblMsg.Text = "installing";
            var ps = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
            Run(ps, "-NoProfile -ExecutionPolicy Bypass -File " + Q(Path.Combine(EngineDir, "setup.ps1")),
                c => { if (c == 0) { txtLog.Visible = false; Check(); } else lblMsg.Text = "the installation stopped (see the log); it goes on by itself at the next start, or press INSTALL"; });
        }

        void LoadProfiles()
        {
            var psi = new ProcessStartInfo(Python, Q(Fvc) + " profiles") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true };
            psi.EnvironmentVariables["FVC_HOME"] = Home;
            using (var p = Process.Start(psi))
            {
                var lines = p.StandardOutput.ReadToEnd().Split('\n').Where(l => l.Trim().StartsWith("[")).ToList();
                p.WaitForExit();
                if (lines.Count == 0) return;
                profiles = json.Deserialize<List<Profile>>(lines.Last());
            }
            var keep = (cmbProfile.SelectedItem as Profile)?.id ?? savedProfile;
            cmbProfile.Items.Clear();
            foreach (var p in profiles) cmbProfile.Items.Add(p);
            var idx = profiles.FindIndex(p => p.id == keep);
            if (cmbProfile.Items.Count > 0) cmbProfile.SelectedIndex = idx >= 0 ? idx : 0;
        }

        const string Media = "Any audio or video file (everything ffmpeg reads)|*.*";

        void PickClips()
        {
            using (var o = new OpenFileDialog { Multiselect = true, Filter = Media })
                if (o.ShowDialog(this) == DialogResult.OK) foreach (var f in o.FileNames) lstClips.Items.Add(f);
        }

        void PickVoice(bool thenConvert = false)
        {
            using (var o = new OpenFileDialog { Filter = Media, Title = "A clean recording of the voice (10 to 30 seconds of speech)" })
            {
                if (o.ShowDialog(this) != DialogResult.OK) return;
                var name = Path.GetFileNameWithoutExtension(o.FileName);
                savedProfile = null;
                Py("profile " + Q(o.FileName) + " " + Q(name), c =>
                {
                    if (c != 0) return;
                    LoadProfiles();
                    var i = profiles.FindIndex(p => p.name == name);
                    if (i >= 0) cmbProfile.SelectedIndex = i;
                    if (thenConvert) Convert();
                }, false);
            }
        }

        void Convert()
        {
            if (!(cmbProfile.SelectedItem is Profile p)) { PickVoice(true); return; }  // no voice yet: asked once
            if (lstClips.Items.Count == 0) { lblMsg.Text = "add the clips first"; return; }
            outputs.Clear(); btnShow.Visible = false; txtLog.Clear(); bar.Value = 0;
            totalS = doneS = startedS = 0; startedAt = null;
            var job = new Dictionary<string, object>
            {
                ["clips"] = lstClips.Items.Cast<string>().ToList(),
                ["profile"] = p.dir,
                ["voice"] = "convert",
                ["quality"] = "speech",
                ["export"] = rStitch.Checked ? "stitched" : rBoth.Checked ? "both" : "individual",
                ["clean"] = true,
                ["steps"] = 30,
            };
            var path = Path.Combine(Path.GetTempPath(), "fvc-job-" + Guid.NewGuid() + ".json");
            File.WriteAllText(path, json.Serialize(job), new UTF8Encoding(false));
            SaveSettings();
            Py("run " + Q(path), c =>
            {
                try { File.Delete(path); } catch { }
                if (c == 0 && outputs.Count > 0) Process.Start("explorer.exe", "/select,\"" + outputs[0] + "\"");
            });
        }

        static string Gb(double b) => $"{b / 1073741824.0:0.0} GB";
        static string Clock(double sec)
        {
            var t = (int)Math.Max(0, Math.Round(sec));
            return t >= 3600 ? $"{t / 3600}:{t / 60 % 60:00}:{t % 60:00}" : $"{t / 60}:{t % 60:00}";
        }

        void UpdateStats()
        {
            bool busy = proc != null;
            double progress = totalS > 0 ? doneS / totalS : 0;
            int pc = (int)Math.Floor(progress * 100);
            hDone.Set(progress, $"{Clock(doneS)} / {Clock(totalS)}");
            if (totalS > 0 && (busy || doneS > 0) && outputs.Count == 0)
            { lblPct.Text = busy ? $"{pc} %" : $"CONVERTED {pc} %"; lblPct.ForeColor = busy ? Color.ForestGreen : Color.DarkOrange; }
            else lblPct.Text = "";
            if (busy && startedAt != null && doneS - startedS > 0.5)
            {
                var el = (DateTime.Now - startedAt.Value).TotalSeconds;
                var rate = (doneS - startedS) / Math.Max(el, 0.001);   // seconds of sound per second
                var left = Math.Max(0, (totalS - doneS) / rate);
                var fill = el / Math.Max(el + left, 1);
                hLeft.Set(fill, Clock(left));
                hEnds.Set(fill, DateTime.Now.AddSeconds(left).ToString("HH:mm"));
                hRun.Set(fill, Clock(el));
                hFps.Set(rate, $"{rate * fps:0.0} fps");                // frames per second at the clips' own rate
            }
            else
            {
                var t = busy ? "…" : "–";
                hLeft.Set(0, t); hEnds.Set(0, t); hRun.Set(0, t); hFps.Set(0, "–");
            }
        }

        // ---------------------------------------------------------------- remembered choices
        string savedProfile;
        void LoadSettings()
        {
            try
            {
                var j = json.Deserialize<Dictionary<string, object>>(File.ReadAllText(Settings));
                savedProfile = j["profile"] as string;
                rKeep.Checked = (string)j["voice"] == "keep"; rConvert.Checked = !rKeep.Checked;
                rStudio.Checked = (string)j["quality"] == "studio"; rSpeech.Checked = !rStudio.Checked;
                var ex = (string)j["export"]; rStitch.Checked = ex == "stitched"; rBoth.Checked = ex == "both"; rOne.Checked = ex == "individual";
                chkClean.Checked = (bool)j["clean"]; chkTop.Checked = (bool)j["top"];
                // the window where it was, on the screen it was on, if that screen is still there
                if (j.TryGetValue("x", out var x) && j.TryGetValue("y", out var y) && j.TryGetValue("w", out var w) && j.TryGetValue("h", out var h))
                {
                    var r = new Rectangle(System.Convert.ToInt32(x), System.Convert.ToInt32(y), System.Convert.ToInt32(w), System.Convert.ToInt32(h));
                    if (Screen.AllScreens.Any(sc => sc.WorkingArea.IntersectsWith(r))) Bounds = r;
                }
            }
            catch { }
        }

        void SaveSettings()
        {
            try
            {
                Directory.CreateDirectory(Home);
                File.WriteAllText(Settings, json.Serialize(new Dictionary<string, object>
                {
                    ["profile"] = (cmbProfile.SelectedItem as Profile)?.id,
                    ["voice"] = rKeep.Checked ? "keep" : "convert",
                    ["quality"] = rStudio.Checked ? "studio" : "speech",
                    ["export"] = rStitch.Checked ? "stitched" : rBoth.Checked ? "both" : "individual",
                    ["clean"] = chkClean.Checked, ["top"] = chkTop.Checked,
                    ["x"] = (WindowState == FormWindowState.Normal ? Bounds : RestoreBounds).X,
                    ["y"] = (WindowState == FormWindowState.Normal ? Bounds : RestoreBounds).Y,
                    ["w"] = (WindowState == FormWindowState.Normal ? Bounds : RestoreBounds).Width,
                    ["h"] = (WindowState == FormWindowState.Normal ? Bounds : RestoreBounds).Height,
                }));
            }
            catch { }
        }
    }
}
