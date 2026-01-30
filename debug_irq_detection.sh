#!/bin/bash

# Script di debug per IRQ detection
echo "=== DEBUG IRQ DETECTION ==="

# Testiamo l'estrazione per IRQ 122
echo "Test IRQ 122:"
irq_line=$(grep "^[ ]*122:" /proc/interrupts)
echo "Riga originale: $irq_line"

if [ -n "$irq_line" ]; then
    irq_description=$(echo "$irq_line" | awk '{for(i=4;i<=NF;i++) printf "%s ", $i; print ""}' | xargs)
    echo "Descrizione estratta: '$irq_description'"
    
    if echo "$irq_description" | grep -qiE "snd|audio|sound|hda|hdaudio|usb.*audio|intel.*audio|realtek|creative|emu|xhci_hcd|ehci_hcd|uhci_hcd"; then
        echo "✓ IRQ 122 PASSATO il controllo audio"
    else
        echo "✗ IRQ 122 FALLITO il controllo audio"
    fi
else
    echo "✗ IRQ 122 non trovata"
fi

echo ""
echo "Test IRQ 126:"
irq_line=$(grep "^[ ]*126:" /proc/interrupts)
echo "Riga originale: $irq_line"

if [ -n "$irq_line" ]; then
    irq_description=$(echo "$irq_line" | awk '{for(i=4;i<=NF;i++) printf "%s ", $i; print ""}' | xargs)
    echo "Descrizione estratta: '$irq_description'"
    
    if echo "$irq_description" | grep -qiE "snd|audio|sound|hda|hdaudio|usb.*audio|intel.*audio|realtek|creative|emu|xhci_hcd|ehci_hcd|uhci_hcd"; then
        echo "✓ IRQ 126 PASSATO il controllo audio"
    else
        echo "✗ IRQ 126 FALLITO il controllo audio"
    fi
else
    echo "✗ IRQ 126 non trovata"
fi

echo ""
echo "=== TEST COMPLETO ==="