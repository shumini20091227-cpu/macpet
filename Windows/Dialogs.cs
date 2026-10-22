namespace MacPet;

internal sealed class ExpressionRow : UserControl
{
    internal ExpressionRow(string title, bool selected, bool removable, Action choose, Action remove)
    {
        Size = new(340, 30);
        BackColor = SystemColors.Menu;
        var label = new Button
        {
            Text = (selected ? "✓  " : "    ") + title, FlatStyle = FlatStyle.Flat,
            TextAlign = ContentAlignment.MiddleLeft, AutoEllipsis = true,
            Dock = DockStyle.Fill, AccessibleName = "切换到「" + title + "」" + (selected ? "，当前表情" : ""),
            UseVisualStyleBackColor = true
        };
        label.FlatAppearance.BorderSize = 0;
        label.Click += (_, _) => choose(); Controls.Add(label);
        if (removable)
        {
            var button = new Button { Text = "×", Width = 30, Dock = DockStyle.Right, FlatStyle = FlatStyle.Flat, AccessibleName = "移除「" + title + "」" };
            button.FlatAppearance.BorderSize = 0;
            button.Click += (_, _) => remove(); Controls.Add(button);
        }
    }
}

internal sealed class DeletionPicker : Form
{
    private readonly CheckedListBox list = new() { Dock = DockStyle.Fill, CheckOnClick = true, IntegralHeight = false, HorizontalScrollbar = true };
    private readonly Label count = new() { AutoSize = true, Text = "已选 0 项", Padding = new(12, 8, 0, 0) };
    private readonly Button delete = new() { Text = "删除所选", AutoSize = true, Enabled = false, DialogResult = DialogResult.OK };
    private bool changing;
    internal List<Expression> SelectedEntries => list.CheckedItems.Cast<Expression>().ToList();
    internal DeletionPicker(List<Expression> entries, Icon icon)
    {
        Text = "批量删除表情"; Icon = icon;
        StartPosition = FormStartPosition.CenterScreen;
        Size = new(500, 520); MinimumSize = new(400, 350);
        ShowInTaskbar = false; TopMost = true;
        Font = SystemFonts.MessageBoxFont!;
        var table = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 4, ColumnCount = 1, Padding = new(12) };
        table.RowStyles.Add(new(SizeType.AutoSize)); table.RowStyles.Add(new(SizeType.AutoSize));
        table.RowStyles.Add(new(SizeType.Percent, 100)); table.RowStyles.Add(new(SizeType.AutoSize));
        table.Controls.Add(new Label { Text = "勾选要删除的表情。导入副本移入回收站，原始文件不受影响。", AutoSize = true, MaximumSize = new(440, 0) }, 0, 0);
        var actions = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill };
        var all = new Button { Text = "全选", AutoSize = true }; all.Click += (_, _) => SelectAll(true);
        var clear = new Button { Text = "取消全选", AutoSize = true }; clear.Click += (_, _) => SelectAll(false);
        actions.Controls.AddRange([all, clear, count]); table.Controls.Add(actions, 0, 1);
        list.Items.AddRange(entries.Cast<object>().ToArray()); table.Controls.Add(list, 0, 2);
        list.ItemCheck += (_, _) => { if (!changing) BeginInvoke(UpdateSelection); };
        var bottom = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill, FlowDirection = FlowDirection.RightToLeft };
        var cancel = new Button { Text = "取消", DialogResult = DialogResult.Cancel, AutoSize = true };
        bottom.Controls.AddRange([delete, cancel]); table.Controls.Add(bottom, 0, 3);
        CancelButton = cancel; Controls.Add(table);
    }
    private void SelectAll(bool check)
    {
        changing = true; list.BeginUpdate();
        for (int i = 0; i < list.Items.Count; i++) list.SetItemChecked(i, check);
        list.EndUpdate(); changing = false; UpdateSelection();
    }
    private void UpdateSelection()
    {
        int selected = list.CheckedItems.Count;
        count.Text = $"已选 {selected} 项";
        delete.Enabled = selected > 0;
        delete.Text = selected > 0 ? $"删除所选（{selected}）" : "删除所选";
    }
}
