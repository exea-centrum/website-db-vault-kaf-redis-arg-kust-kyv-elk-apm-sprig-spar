#!/bin/bash

# Skrypt do zmniejszania zasobów w plikach YAML
# Przeszukuje pliki YAML i zmniejsza wartości requests/limits

set -e

# Funkcja do zmniejszania pojedynczej wartości
zmniejsz_wartosc() {
    local wartosc="$1"
    local procent="$2"
    local typ="$3"  # "cpu" lub "memory"
    
    # Oblicz mnożnik (np. dla 50% -> 0.5, dla 30% -> 0.7)
    local mnoznik=$(echo "scale=2; (100 - $procent) / 100" | bc)
    
    # CPU - obsługa milicores (m) i jednostek dziesiętnych
    if [[ "$typ" == "cpu" ]]; then
        if [[ "$wartosc" == *"m" ]]; then
            # Milicores (np. 100m, 250m)
            local liczba=$(echo "$wartosc" | sed 's/m//')
            local nowa_liczba=$(echo "$liczba * $mnoznik" | bc | awk '{print int($1+0.5)}')
            # Minimalna wartość to 1m
            if [[ $nowa_liczba -lt 1 ]]; then
                nowa_liczba=1
            fi
            echo "${nowa_liczba}m"
        elif [[ "$wartosc" =~ ^[0-9.]+$ ]]; then
            # Jednostki dziesiętne (np. 0.5, 1.0)
            local nowa_wartosc=$(echo "$wartosc * $mnoznik" | bc -l)
            # Formatowanie do 3 miejsc po przecinku i usuwanie zer
            echo "$nowa_wartosc" | awk '{printf "%.3f", $1}' | sed 's/0*$//' | sed 's/\.$//'
        else
            # Nieznany format - zwróć oryginał
            echo "$wartosc"
        fi
    
    # MEMORY - obsługa różnych jednostek (Ki, Mi, Gi)
    elif [[ "$typ" == "memory" ]]; then
        if [[ "$wartosc" =~ ^([0-9]+)([KMGT]i?)$ ]]; then
            local liczba="${BASH_REMATCH[1]}"
            local jednostka="${BASH_REMATCH[2]}"
            local nowa_liczba=$(echo "$liczba * $mnoznik" | bc | awk '{print int($1+0.5)}')
            
            # Minimalne wartości w zależności od jednostki
            case "$jednostka" in
                "Ki"|"K")
                    if [[ $nowa_liczba -lt 4 ]]; then nowa_liczba=4; fi
                    ;;
                "Mi"|"M")
                    if [[ $nowa_liczba -lt 16 ]]; then nowa_liczba=16; fi
                    ;;
                "Gi"|"G")
                    if [[ $nowa_liczba -lt 1 ]]; then nowa_liczba=1; fi
                    # Dla Gi zaokrąglamy do 0.1
                    nowa_liczba=$(echo "$nowa_liczba" | awk '{printf "%.1f", $1}' | sed 's/\.0$//')
                    ;;
                *)
                    # Dla innych jednostek minimalna wartość 1
                    if [[ $nowa_liczba -lt 1 ]]; then nowa_liczba=1; fi
                    ;;
            esac
            
            echo "${nowa_liczba}${jednostka}"
        elif [[ "$wartosc" =~ ^[0-9]+$ ]]; then
            # Bez jednostki (domyślnie bajty) - konwertuj do Mi
            local nowa_liczba=$(echo "$wartosc * $mnoznik / 1048576" | bc | awk '{print int($1+0.5)}')
            if [[ $nowa_liczba -lt 1 ]]; then nowa_liczba=1; fi
            echo "${nowa_liczba}Mi"
        else
            # Nieznany format - zwróć oryginał
            echo "$wartosc"
        fi
    else
        echo "$wartosc"
    fi
}

# Funkcja do przetwarzania pliku YAML
przetworz_plik() {
    local plik="$1"
    local procent="$2"
    
    echo "Przetwarzanie: $plik (zmniejszenie o ${procent}%)"
    
    # Sprawdź czy plik istnieje i ma zasoby
    if ! grep -q "resources:" "$plik"; then
        echo "  Pomijam: brak sekcji resources"
        return 0
    fi
    
    # Policz ile sekcji resources
    local ilosc_sekcji=$(grep -c "resources:" "$plik")
    echo "  Znaleziono $ilosc_sekcji sekcji resources"
    
    # Tworzymy kopię zapasową
    cp "$plik" "${plik}.bak"
    
    # Przetwarzanie pliku
    local temp_plik=$(mktemp)
    local in_resources=false
    local in_requests=false
    local in_limits=false
    local indent=""
    
    while IFS= read -r linia; do
        # Sprawdzamy czy wchodzimy do sekcji resources
        if [[ "$linia" =~ ^([[:space:]]*)resources: ]]; then
            in_resources=true
            in_requests=false
            in_limits=false
            indent="${BASH_REMATCH[1]}"
            echo "$linia" >> "$temp_plik"
            continue
        fi
        
        # Sprawdzamy czy wychodzimy z sekcji resources
        if $in_resources && [[ "$linia" =~ ^[[:space:]]*[^[:space:]#] ]] && ! [[ "$linia" =~ ^[[:space:]]+(requests|limits|cpu|memory): ]]; then
            in_resources=false
            in_requests=false
            in_limits=false
        fi
        
        # Obsługa requests
        if $in_resources && [[ "$linia" =~ ^([[:space:]]+)requests: ]]; then
            in_requests=true
            in_limits=false
            indent="${BASH_REMATCH[1]}"
            echo "$linia" >> "$temp_plik"
            continue
        fi
        
        # Obsługa limits
        if $in_resources && [[ "$linia" =~ ^([[:space:]]+)limits: ]]; then
            in_limits=true
            in_requests=false
            indent="${BASH_REMATCH[1]}"
            echo "$linia" >> "$temp_plik"
            continue
        fi
        
        # Zmiana wartości CPU w requests
        if $in_requests && [[ "$linia" =~ ^([[:space:]]+)cpu:[[:space:]]*[\"\']?([0-9.m]+)[\"\']? ]]; then
            local biale_znaki="${BASH_REMATCH[1]}"
            local stara_wartosc="${BASH_REMATCH[2]}"
            local nowa_wartosc=$(zmniejsz_wartosc "$stara_wartosc" "$procent" "cpu")
            echo "${biale_znaki}cpu: \"$nowa_wartosc\"" >> "$temp_plik"
            echo "    CPU requests: $stara_wartosc -> $nowa_wartosc"
            continue
        fi
        
        # Zmiana wartości memory w requests
        if $in_requests && [[ "$linia" =~ ^([[:space:]]+)memory:[[:space:]]*[\"\']?([0-9KMGTi]+)[\"\']? ]]; then
            local biale_znaki="${BASH_REMATCH[1]}"
            local stara_wartosc="${BASH_REMATCH[2]}"
            local nowa_wartosc=$(zmniejsz_wartosc "$stara_wartosc" "$procent" "memory")
            echo "${biale_znaki}memory: \"$nowa_wartosc\"" >> "$temp_plik"
            echo "    Memory requests: $stara_wartosc -> $nowa_wartosc"
            continue
        fi
        
        # Zmiana wartości CPU w limits
        if $in_limits && [[ "$linia" =~ ^([[:space:]]+)cpu:[[:space:]]*[\"\']?([0-9.m]+)[\"\']? ]]; then
            local biale_znaki="${BASH_REMATCH[1]}"
            local stara_wartosc="${BASH_REMATCH[2]}"
            local nowa_wartosc=$(zmniejsz_wartosc "$stara_wartosc" "$procent" "cpu")
            echo "${biale_znaki}cpu: \"$nowa_wartosc\"" >> "$temp_plik"
            echo "    CPU limits: $stara_wartosc -> $nowa_wartosc"
            continue
        fi
        
        # Zmiana wartości memory w limits
        if $in_limits && [[ "$linia" =~ ^([[:space:]]+)memory:[[:space:]]*[\"\']?([0-9KMGTi]+)[\"\']? ]]; then
            local biale_znaki="${BASH_REMATCH[1]}"
            local stara_wartosc="${BASH_REMATCH[2]}"
            local nowa_wartosc=$(zmniejsz_wartosc "$stara_wartosc" "$procent" "memory")
            echo "${biale_znaki}memory: \"$nowa_wartosc\"" >> "$temp_plik"
            echo "    Memory limits: $stara_wartosc -> $nowa_wartosc"
            continue
        fi
        
        # Jeśli żaden z powyższych przypadków, zapisz oryginalną linię
        echo "$linia" >> "$temp_plik"
        
    done < "$plik"
    
    # Zastąp oryginalny plik
    mv "$temp_plik" "$plik"
    echo "  Zakończono! Kopia zapasowa: ${plik}.bak"
    echo ""
}

# Główna funkcja
main() {
    if [[ $# -lt 1 ]]; then
        echo "Użycie: $0 <ścieżka-do-pliku-lub-katalogu> [procent-zmniejszenia]"
        echo "Przykład: $0 deployment.yaml 50"
        echo "Przykład: $0 /sciezka/do/katalogu 30"
        echo "Przykład: $0 *.yaml 40"
        exit 1
    fi
    
    local sciezka="$1"
    local procent="${2:-50}"  # Domyślnie 50%
    
    # Walidacja procentu
    if ! [[ "$procent" =~ ^[0-9]+$ ]] || [[ "$procent" -lt 1 ]] || [[ "$procent" -gt 90 ]]; then
        echo "Błąd: Procent musi być liczbą od 1 do 90"
        exit 1
    fi
    
    echo "=== Zmniejszanie zasobów w plikach YAML o ${procent}% ==="
    echo ""
    
    local liczba_plikow=0
    
    # Obsługa pojedynczego pliku
    if [[ -f "$sciezka" ]]; then
        przetworz_plik "$sciezka" "$procent"
        liczba_plikow=1
        
    # Obsługa katalogu
    elif [[ -d "$sciezka" ]]; then
        # Znajdź wszystkie pliki YAML w katalogu
        while IFS= read -r plik; do
            przetworz_plik "$plik" "$procent"
            ((liczba_plikow++))
        done < <(find "$sciezka" -name "*.yaml" -o -name "*.yml")
        
    # Obsługa wzorca (np. *.yaml)
    else
        for plik in $sciezka; do
            if [[ -f "$plik" ]]; then
                przetworz_plik "$plik" "$procent"
                ((liczba_plikow++))
            fi
        done
    fi
    
    if [[ $liczba_plikow -eq 0 ]]; then
        echo "Nie znaleziono żadnych plików YAML do przetworzenia."
    else
        echo "=== Przetworzono $liczba_plikow plików ==="
        echo ""
        echo "UWAGA: Pliki zostały zmodyfikowane!"
        echo "Kopie zapasowe mają rozszerzenie .bak"
        echo "Przed wdrożeniem przetestuj zmiany!"
    fi
}

# Sprawdź czy bc jest zainstalowany (potrzebne do obliczeń)
if ! command -v bc &> /dev/null; then
    echo "Błąd: Program 'bc' nie jest zainstalowany"
    echo "Zainstaluj: sudo apt-get install bc (Debian/Ubuntu)"
    echo "            sudo yum install bc (RHEL/CentOS)"
    exit 1
fi

# Uruchom główną funkcję
main "$@"