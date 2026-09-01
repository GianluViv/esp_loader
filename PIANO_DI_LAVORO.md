# ESP Loader — piano di lavoro

## 1. Obiettivo

Realizzare un'applicazione Flutter Desktop per Windows e Linux dedicata a due funzioni principali:

1. programmazione di microcontrollori Espressif tramite le utility ufficiali da linea di comando;
2. monitoraggio della porta seriale, con passaggio automatico dalla programmazione al monitor.

L'applicazione deve offrire un'interfaccia operativa semplice e mantenere l'output testuale completo dei comandi in un pannello tecnico normalmente nascosto.

## 2. Progetti di riferimento

### `proto_flutter`

Viene usato come riferimento per:

- struttura di un progetto Flutter multipiattaforma;
- target Windows e Linux;
- script di rilascio Windows;
- distribuzione Linux tramite AppImage;
- convenzioni generali del progetto desktop.

### `collaudo_ariosa_global`

Viene usato come riferimento per:

- esecuzione di `esptool` come processo esterno;
- acquisizione asincrona di standard output e standard error;
- rilevamento delle porte seriali;
- selezione di file binari e indirizzi;
- cancellazione della flash;
- interruzione del processo;
- inclusione di `esptool` nella distribuzione Windows;
- interfaccia Fluent e gestione della finestra desktop.

Il codice esistente sarà adattato e separato dalle parti specifiche del banco di collaudo.

## 3. Principi progettuali

- Un'unica base di codice per Windows e Linux.
- Separazione fra interfaccia, configurazione, servizi seriali e processi esterni.
- Nessuna dipendenza della logica operativa dai widget Flutter.
- Esclusione reciproca fra flash e monitor sulla stessa porta.
- Output tecnico conservato, ma non mostrato nell'interfaccia principale.
- Configurazioni persistenti e profili di programmazione riutilizzabili.
- Interfaccia utilizzabile anche con finestre di dimensioni ridotte.
- Operazioni lunghe sempre annullabili e accompagnate da stato e avanzamento.

## 4. Fasi di lavoro

### Fase 1 — Demo dell'interfaccia utente

#### Scopo

Costruire direttamente in Flutter una demo navigabile, alimentata da dati simulati e priva inizialmente di accesso reale alla seriale e a `esptool`.

#### Contenuti

- tema Fluent chiaro e scuro;
- finestra desktop e navigazione principale;
- pagine **Programmazione**, **Monitor**, **Plot** e **Impostazioni**;
- pannello tecnico/log normalmente nascosto;
- stati simulati di attesa, programmazione, successo, errore e cancellazione;
- layout adattabile a Windows e Linux.

#### Pagina Programmazione

- selezione del chip Espressif;
- selezione e aggiornamento della porta seriale;
- baud rate di caricamento;
- lista dinamica di file `.bin` con indirizzo e abilitazione individuale;
- aggiunta, rimozione e riordinamento dei binari;
- SPI mode, frequenza e dimensione flash;
- comandi Programma, Interrompi, Cancella flash e Combina binari;
- attivazione autoload;
- opzione per aprire automaticamente il monitor al termine;
- indicatore di avanzamento e risultato sintetico.

#### Pagina Monitor

- porta, baud rate standard o personalizzato;
- data bit, stop bit, parità e controllo di flusso;
- aggiorna porte, connetti, disconnetti e reset;
- terminale con pausa, cancellazione, ritorno a capo e timestamp;
- limite massimo di righe;
- ricerca e filtri include/escludi;
- copia completa, filtrata o visibile;
- salvataggio del log;
- campo per l'invio di testo o dati;
- dati seriali simulati per valutare usabilità e prestazioni visive.

#### Pagina Plot

- area grafico dimostrativa;
- selezione delle serie;
- pausa, pulizia e finestra temporale;
- anteprima di dati numerici simulati.

#### Criteri di completamento

- la demo si avvia su Linux e mantiene la struttura necessaria per Windows;
- tutte le pagine sono navigabili;
- i controlli principali reagiscono e mostrano stati simulati;
- il pannello tecnico resta nascosto nel normale flusso operativo;
- la revisione con l'utente produce un elenco di modifiche e funzioni approvate.

### Fase 2 — Consolidamento delle specifiche

Definire dopo la revisione della demo:

- famiglie di chip Espressif supportate;
- matrice precisa delle funzioni da replicare da Flash Download Tool;
- numero massimo e comportamento delle righe di caricamento;
- formato e portabilità dei profili;
- regole definitive dell'autoload;
- funzionalità definitive del monitor e del plot;
- necessità e comportamento della decodifica tramite file ELF;
- priorità fra funzioni essenziali e avanzate.

### Fase 3 — Architettura applicativa

Creare moduli separati per:

- configurazione e persistenza;
- modelli di chip, target binari e profili;
- rilevamento porte;
- gestione dei processi Espressif;
- programmazione e cancellazione flash;
- monitor seriale;
- autoload;
- log tecnico;
- coordinamento delle operazioni.

Una macchina a stati centrale controllerà almeno gli stati: inattivo, monitor collegato, preparazione, programmazione, cancellazione, completato, errore e annullamento.

### Fase 4 — Integrazione delle utility Espressif

- individuazione automatica dell'eseguibile distribuito con l'app;
- eseguibili distinti per Windows e Linux;
- percorso manuale come fallback;
- costruzione verificabile degli argomenti da linea di comando;
- acquisizione in tempo reale di output ed errori;
- interpretazione di stato, progresso e messaggi rilevanti;
- timeout e interruzione controllata;
- conservazione del log tecnico completo.

### Fase 5 — Motore di programmazione

- selezione o rilevamento del chip;
- programmazione di uno o più binari a indirizzi configurabili;
- scelta di baud rate, SPI mode, frequenza e dimensione flash;
- cancellazione flash;
- arresto dell'operazione;
- verifica preventiva di file, indirizzi e sovrapposizioni;
- profili salvabili, duplicabili, esportabili e importabili;
- eventuale combinazione dei binari;
- risultato finale comprensibile senza consultare il log tecnico.

Le funzioni avanzate o legate alla sicurezza verranno introdotte solo dopo la definizione della matrice della Fase 2.

### Fase 6 — Autoload

- osservazione di uno o più file configurati;
- debounce degli eventi ripetuti generati dal compilatore;
- verifica che il file sia stabile, chiuso e leggibile;
- prevenzione di programmazioni duplicate;
- accodamento di una modifica rilevata durante un flash;
- stato visibile: in ascolto, modifica rilevata, attesa, flash e risultato;
- possibilità di sospendere temporaneamente l'autoload;
- passaggio opzionale al monitor dopo ogni flash riuscito.

### Fase 7 — Monitor seriale

- enumerazione e aggiornamento delle porte su Windows e Linux;
- configurazione completa della linea seriale;
- apertura e chiusura robuste;
- ricezione continua senza bloccare l'interfaccia;
- decodifica testuale configurabile e visualizzazione esadecimale;
- trasmissione con terminatore configurabile;
- controllo di DTR e RTS quando disponibile;
- reset del dispositivo;
- pausa visuale senza perdita opzionale dei dati;
- buffer circolare con limite configurabile;
- timestamp, ricerca, filtri, copia e salvataggio;
- gestione di rimozione del dispositivo e riconnessione.

### Fase 8 — Coordinamento flash e monitor

Flusso previsto:

```text
chiusura monitor → acquisizione esclusiva della porta → flash
→ eventuale reset → attesa configurabile → riapertura monitor
```

Il coordinamento dovrà funzionare anche con autoload attivo e gestire errori, cancellazioni e scollegamenti fisici.

### Fase 9 — Plot e analisi

- estrazione di valori numerici tramite separatore, espressione regolare o formato strutturato;
- visualizzazione di più serie;
- pausa, zoom, pulizia e finestra temporale;
- visualizzazione coordinata con il terminale;
- eventuale decodifica degli indirizzi tramite ELF, se confermata nella Fase 2.

### Fase 10 — Impostazioni e profili

Persistenza di:

- ultima porta e configurazione seriale;
- profili di programmazione;
- file, indirizzi e parametri flash;
- opzioni autoload;
- comportamento post-flash;
- filtri del monitor;
- tema, dimensione e posizione della finestra.

I profili useranno percorsi relativi quando possibile e potranno essere esportati e importati.

### Fase 11 — Test e collaudo

- test della costruzione dei comandi;
- test del parser dell'output Espressif;
- test delle validazioni dei segmenti flash;
- test dell'autoload e del debounce;
- test dei buffer, della ricerca e dei filtri seriali;
- test con porte seriali virtuali;
- test su dispositivi reali per ogni famiglia supportata;
- test di scollegamento, timeout, file incompleto e flash interrotto;
- verifica su Windows e Linux.

### Fase 12 — Distribuzione

- bundle Windows;
- eventuale eseguibile Windows portabile;
- bundle Linux e AppImage;
- inclusione delle utility Espressif per la piattaforma corretta;
- inclusione delle licenze;
- controllo iniziale delle dipendenze;
- diagnostica dei permessi seriali Linux;
- guida di installazione e risoluzione problemi.

## 5. Traguardi

| Traguardo | Risultato |
| --- | --- |
| M1 | Demo UI approvata |
| M2 | Specifiche funzionali congelate |
| M3 | Flash reale funzionante su Windows e Linux |
| M4 | Autoload affidabile |
| M5 | Monitor seriale completo |
| M6 | Integrazione automatica flash-monitor |
| M7 | Plot e funzioni avanzate concordate |
| M8 | Release collaudata e distribuibile |

## 6. Decisione tecnologica per la demo

La demo viene realizzata direttamente in Flutter, non in HTML/CSS/JavaScript.

Motivazioni:

- i controlli desktop definitivi possono essere valutati subito;
- la demo diventa la base reale dell'applicazione;
- non è necessaria una riscrittura successiva;
- gestione finestra, dialoghi file, scorciatoie e layout vengono verificati nel contesto corretto;
- è possibile sostituire gradualmente i dati simulati con i servizi reali;
- emergono presto eventuali differenze fra Windows e Linux.

## 7. Primo passo operativo

Creare il progetto Flutter desktop in `esp_loader`, limitato ai target Windows e Linux, e implementare la struttura navigabile della Fase 1 prima di collegare dipendenze hardware o processi esterni.
