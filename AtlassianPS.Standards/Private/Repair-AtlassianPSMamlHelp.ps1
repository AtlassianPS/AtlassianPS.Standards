function Repair-AtlassianPSMamlHelp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$MamlFile,

        [Parameter(Mandatory)]
        [Object[]]$CommandHelp
    )

    $xml = [xml](Get-Content -LiteralPath $MamlFile -Raw)
    $ns = [System.Xml.XmlNamespaceManager]::new($xml.NameTable)
    $ns.AddNamespace('command', 'http://schemas.microsoft.com/maml/dev/command/2004/10')
    $ns.AddNamespace('dev', 'http://schemas.microsoft.com/maml/dev/2004/10')
    $ns.AddNamespace('maml', 'http://schemas.microsoft.com/maml/2004/10')

    foreach ($help in $CommandHelp) {
        $cmdNode = $xml.SelectSingleNode("//command:command[command:details/command:name='$($help.Title)']", $ns)
        if (-not $cmdNode) { continue }

        $exNodes = @($cmdNode.SelectNodes('command:examples/command:example', $ns))
        for ($i = 0; $i -lt $exNodes.Count -and $i -lt $help.Examples.Count; $i++) {
            $ex = $exNodes[$i]
            $remarksMd = $help.Examples[$i].Remarks
            if (-not $remarksMd) { continue }
            $codeText = ''
            $proseText = $remarksMd
            $fence = [regex]::Match($remarksMd, '(?s)```[a-zA-Z0-9_+\-]*\r?\n(.*?)\r?\n```')
            if ($fence.Success) {
                $codeText = $fence.Groups[1].Value.TrimEnd()
                $proseText = ($remarksMd.Substring(0, $fence.Index) + $remarksMd.Substring($fence.Index + $fence.Length)).Trim()
            }
            $intro = $ex.SelectSingleNode('maml:introduction', $ns)
            if ($intro) { [void]$ex.RemoveChild($intro) }
            $codeNode = $ex.SelectSingleNode('dev:code', $ns)
            if (-not $codeNode) {
                $codeNode = $xml.CreateElement('dev', 'code', 'http://schemas.microsoft.com/maml/dev/2004/10')
                [void]$ex.AppendChild($codeNode)
            }
            $codeNode.InnerText = $codeText
            $remarksNode = $ex.SelectSingleNode('dev:remarks', $ns)
            if (-not $remarksNode) {
                $remarksNode = $xml.CreateElement('dev', 'remarks', 'http://schemas.microsoft.com/maml/dev/2004/10')
                [void]$ex.AppendChild($remarksNode)
            }
            while ($remarksNode.HasChildNodes) { [void]$remarksNode.RemoveChild($remarksNode.FirstChild) }
            foreach ($para in ($proseText -split "\r?\n\r?\n")) {
                if (-not $para.Trim()) { continue }
                $pn = $xml.CreateElement('maml', 'para', 'http://schemas.microsoft.com/maml/2004/10')
                $pn.InnerText = $para
                [void]$remarksNode.AppendChild($pn)
            }
        }

        $paramMap = @{}
        foreach ($p in $help.Parameters) { $paramMap[$p.Name] = $p }
        foreach ($pNode in $cmdNode.SelectNodes('.//command:parameter', $ns)) {
            $pName = $pNode.SelectSingleNode('maml:name', $ns).InnerText
            if (-not $paramMap.ContainsKey($pName)) { continue }
            $p = $paramMap[$pName]
            $aliasText = if ($p.Aliases) { $p.Aliases -join ', ' } else { 'none' }
            $pNode.SetAttribute('aliases', $aliasText)
            $byVal = $false
            $byName = $false
            foreach ($set in $p.ParameterSets) {
                if ($set.ValueFromPipeline) { $byVal = $true }
                if ($set.ValueFromPipelineByPropertyName) { $byName = $true }
            }
            $pipelineText = if ($byVal -and $byName) {
                'True (ByValue, ByPropertyName)'
            }
            elseif ($byVal) { 'True (ByValue)' }
            elseif ($byName) { 'True (ByPropertyName)' }
            else { 'False' }
            $pNode.SetAttribute('pipelineInput', $pipelineText)
            if ($pNode.ParentNode.LocalName -eq 'parameters' -and $null -ne $p.DefaultValue) {
                $existing = $pNode.SelectSingleNode('dev:defaultValue', $ns)
                if ($existing) { [void]$pNode.RemoveChild($existing) }
                $dv = $xml.CreateElement('dev', 'defaultValue', 'http://schemas.microsoft.com/maml/dev/2004/10')
                $dv.InnerText = $p.DefaultValue
                [void]$pNode.AppendChild($dv)
            }
        }
    }

    $xml.Save($MamlFile)
}
