# System IoT monitorujący pracę pralki

Sieci czujnikowe i internetu rzeczy  
Realizacja 2026L  
Autorzy: Krzysztof Fijałkowski, Tomasz Owienko

# Cel projektu

Celem projektu jest implementacja systemu monitorowania cyklu pracy pralki oraz powiadamiania o jego zakończeniu za pomocą mikrokontrolera ESP32, inteligentnego gniazdka oraz chmury AWS.

# Działanie systemu

- Inteligentne gniazdko mierzy zużycie energii przez pralkę i wysyła je na topic MQTT (A) w chmurze AWS  
- Funkcja serverless pobiera wiadomości MQTT w paczkach i zapisuje je do bazy danych szeregów czasowych  
  - Gdy zużycie energii wzrasta, jest to rejestrowane jako rozpoczęcie cyklu prania  
  - Gdy zużycie energii spadnie na określony czas (np. 3 minuty), jest to rejestrowane jako zakończenie cyklu prania  
- W momencie rozpoczęcia / zakończenia cyklu, funkcja publikuje wiadomość na innym topicu (B)  
- Wiadomość jest odbierana przez urządzenie ESP32 wyposażone w buzzer i przycisk; buzzer zaczyna wydawać dźwięk  
- Jednocześnie na telefon z systemem Android wysyłane jest powiadomienie push  
- Naciśnięcie przycisku lub kliknięcie powiadomienia push przez użytkownika powoduje opublikowanie wiadomości na topicu (B)  
- ESP32 odbiera wiadomość z topicu B i wyłącza buzzer  
- W dowolnym momencie powinna istnieć możliwość podglądu surowych odczytów z inteligentnego gniazdka oraz wykrytych zdarzeń (rozpoczęcie cyklu, zakończenie cyklu, wyciszenie brzęczyka) za pośrednictwem interfejsu webowego lub aplikacji mobilnej

# Wybrane czujniki

- Seeed Xiao ESP32-S3 \- WiFi/Bluetooth \- Seeedstudio 113991114  
  - Gniazdko ma możliwość pracy jako publisher MQTT  
- Moduł z buzzerem aktywnym z generatorem \- SENV0005  
- Tact Switch 12x12mm \- przyciski kolorowe \- 4szt. \- SparkFun PRT-14460  
- Zestaw płytka stykowa 830 \+ przewody \+ moduł zasilający  
- Zestaw rezystorów CF THT 1/4W opisany \- 160szt.  
- Zasilacz impulsowy 5V/3A 15W \- wtyk DC 5,5/2,1mm  
- Shelly Plug S Gen3 \- inteligentne gniazdko WiFi/Bluetooth/Matter z pomiarem energii \- białe

# Architektura rozwiązania

## Schemat połączeń

![](assets/connections.png)

## Wykorzystane usługi chmurowe

- AWS IoT Core: broker MQTT, wspiera mTLS i może wywoływać funkcje AWS Lambda.  
- Amazon Timestream: baza danych przeznaczona do szeregów czasowych  
- AWS Lambda: Zapewnia środowisko uruchomieniowe dla zdefiniowanej logiki biznesowej w chmurze  
- AWS API Gateway: obsługuje żądania wyciszenia buzzera wysłanego z telefonu  
- Amazon CloudWatch Dashboards: wizualizuje szeregi czasowe, dostęp nie wymaga logowania do konta AWS

## Schemat komunikacji

```mermaid
---
config:
  layout: elk
  theme: neutral
---
flowchart TD
    subgraph WLAN [Sieć WLAN]
        gniazdko[Smart Plug]
        esp[ESP32 + Buzzer + Przycisk]
    end
    
    subgraph AWS [AWS]
        iot[AWS IoT Core
        MQTT Broker
        Topic z odczytami i zdarzeniami]
        iot@{ icon: "aws:arch-aws-iot-core" }
        lambda_proc[AWS Lambda
        Logika biznesowa]
        lambda_proc@{ icon: "aws:arch-aws-lambda" }
        db[(Amazon Timestream
        Baza szeregów czasowych)]
        db@{ icon: "aws:arch-amazon-timestream" }
        lambda_webhook[AWS Lambda
        Obsługa Żądań Zewnętrznych]
        lambda_webhook@{ icon: "aws:arch-aws-lambda" }
        api[AWS API Gateway]
        api@{ icon: "aws:arch-amazon-api-gateway" }
        cloudwatch[Amazon CloudWatch
        Wizualizacja danych]
        cloudwatch@{ icon: "aws:arch-amazon-cloudwatch" }
    end
    
    subgraph APKA [Urządzenie mobilne]
        phone[Aplikacja mobilna Discord / Telegram]
        phone_web[Przeglądarka internetowa]
    end

    gniazdko -- Publikacja pomiaru zużycia mocy<br>[MQTT / mTLS] --> iot
    iot -- Pobieranie odczytów zużycia mocy w paczkach<br>[MQTT / mTLS] --> lambda_proc
    lambda_proc -- Zapis i rotacja rekordów--> db
    lambda_proc -- Wykrycie zakończenia cyklu prania<br>[MQTT / mTLS] --> iot
    
    iot -- Nasłuchiwanie wiadomości o zakończeniu cyklu prania<br>[MQTT / mTLS] --> esp
    esp -- Wciśnięcie przycisku<br>[MQTT / mTLS] --> iot
    
    lambda_proc -- Wywołanie POST Discord / Telegram API --> phone
    phone -- Żądanie wyciszenia buzzera<br>[HTTPS] --> api
    api -- Integracja Proxy --> lambda_webhook
    lambda_webhook -- Wyciszenie urządzenia<br>[MQTT / mTLS] --> iot
    
    cloudwatch -. "Zapytania SQL" .-> db
    phone_web -. "Dostęp do dashboardów" .-> cloudwatch
```

## Przepływ komunikacji

```mermaid
---
config:
  layout: elk
  theme: neutral
---
sequenceDiagram
    participant Plug as Smart Plug (Gniazdko)
    participant IoT as AWS IoT Core
    participant Lambda as AWS Lambda (Przetwarzanie)
    participant DB as Amazon Timestream
    participant ESP as Node ESP32 
    participant Phone as Urządzenie mobilne
    participant API as API Gateway + Lambda Webhook

    Note over Plug, DB: Faza inicjalizacji i ciągłego monitoringu cyklu
    Plug->>IoT: Publikacja Temat A - moc 2300W
    IoT->>Lambda: Trigger na podstawie AWS IoT Rule
    Lambda->>DB: Archiwizacja i rejestracja pomiaru
    Lambda->>Lambda: Estymacja trendu: znaczny skok (Flaga START)
    Lambda->>IoT: Publikacja Temat B: akcja START

    Note over Plug, Lambda: Zakończenie pracy agregatu domowego
    Plug->>IoT: Publikacja Temat A: moc 1.5W
    IoT->>Lambda: Trigger pomiaru post-operacyjnego
    Lambda->>DB: Zapis i ewaluacja
    Lambda->>Lambda: Warunek t ponad 3 min, P ponizej prog
    
    Lambda->>IoT: Publikacja Temat B: akcja KONIEC BUZZER ON
    IoT->>ESP: Propagacja subskrypcji wlaczajaca Buzzer
    Lambda->>Phone: Powiadomienie Push z interaktywnym przyciskiem

    Note over ESP, Phone: Faza interakcji i wyciszenia układu operatywnego
    
    alt Interakcja sprzętowa ze strony użytkownika
        ESP->>IoT: Wciśnięcie przycisku - Publikacja Temat B: akcja WYCISZ
    else Interakcja mobilna ze strony użytkownika
        Phone->>API: Wywołanie opcji Wycisz HTTP Webhook
        API->>IoT: Bezserwerowa publikacja Temat B: akcja WYCISZ
    end
    
    IoT->>ESP: Odebranie żądania sprzętowego
    ESP->>ESP: Odłączenie zasilania od Buzzera
```

# Konfiguracje

## Konfiguracja wtyczki

Używając aplikacji shelly konfigurujemy wtyczkę wybierając opcję dodania urządzenia:  

![](assets/shelly1.png)

Następnie w ustawieniach tej wtyczki mamy możliwość ustawienia serwera MQTT  

![](assets/shelly2.png)

## Konfiguracja płytki i środowiska

Konfiguracja zaczęła się instalacją i ustawieniem oprogramowania Arduino IDE oraz zainstalowanie w nim biblioteki esp32  

![](assets/arduino_ide1.png)

Następnie skonfigurowanie odpowiedniej płytki i portu na którym jest podłączona  

![](assets/arduino_ide2.png)

Ostatnim krokiem było napisanie odpowiedniego kodu programu jak i go wgranie.

# Aktualny stan projektu:

- Działający układ z przykładowym programem (naciśnięcie przycisku powoduje zmian stanu brzęczyka)  
  - nagranie: [https://photos.app.goo.gl/jPcqguUSQTLhYxKf7](https://photos.app.goo.gl/jPcqguUSQTLhYxKf7)  
- Działająca wtyczka pobiera aktualne dane

![](assets/demo1.png)
