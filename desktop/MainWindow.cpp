#include "MainWindow.h"
#include "ApngGenerator.h"

#include <QFileDialog>
#include <QMessageBox>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QPushButton>
#include <QSpinBox>
#include <QListWidget>
#include <QLabel>
#include <QImageReader>
#include <QScrollArea>
#include <QStatusBar>
#include <QPixmap>
#include <QIcon>

MainWindow::MainWindow(QWidget *parent)
    : QMainWindow(parent),
      m_currentPreviewFrame(0),
      m_isPreviewing(false)
{
    setupUi();
    refreshFrameList();
}

MainWindow::~MainWindow()
{
}

void MainWindow::setupUi()
{
    setWindowTitle("APNG 生成器");
    resize(900, 600);

    QWidget *centralWidget = new QWidget(this);
    setCentralWidget(centralWidget);

    QHBoxLayout *mainLayout = new QHBoxLayout(centralWidget);

    // 左侧
    QVBoxLayout *leftLayout = new QVBoxLayout();
    m_frameList = new QListWidget(this);
    m_frameList->setIconSize(QSize(80, 80));
    m_frameList->setSelectionMode(QAbstractItemView::SingleSelection);
    connect(m_frameList, &QListWidget::currentRowChanged,
            this, &MainWindow::onFrameSelectionChanged);
    leftLayout->addWidget(m_frameList);

    QHBoxLayout *buttonRow1 = new QHBoxLayout();
    QPushButton *addButton = new QPushButton("添加", this);
    QPushButton *removeButton = new QPushButton("删除", this);
    QPushButton *upButton = new QPushButton("上移", this);
    QPushButton *downButton = new QPushButton("下移", this);
    connect(addButton, &QPushButton::clicked, this, &MainWindow::addFrames);
    connect(removeButton, &QPushButton::clicked, this, &MainWindow::removeSelectedFrame);
    connect(upButton, &QPushButton::clicked, this, &MainWindow::moveFrameUp);
    connect(downButton, &QPushButton::clicked, this, &MainWindow::moveFrameDown);
    buttonRow1->addWidget(addButton);
    buttonRow1->addWidget(removeButton);
    buttonRow1->addWidget(upButton);
    buttonRow1->addWidget(downButton);
    leftLayout->addLayout(buttonRow1);

    QHBoxLayout *delayLayout = new QHBoxLayout();
    QLabel *delayLabel = new QLabel("帧延迟 (1/100s):", this);
    m_delaySpinBox = new QSpinBox(this);
    m_delaySpinBox->setRange(1, 10000);
    m_delaySpinBox->setValue(10);
    connect(m_delaySpinBox, QOverload<int>::of(&QSpinBox::valueChanged),
            this, &MainWindow::onDelayChanged);
    delayLayout->addWidget(delayLabel);
    delayLayout->addWidget(m_delaySpinBox);
    leftLayout->addLayout(delayLayout);

    QHBoxLayout *loopLayout = new QHBoxLayout();
    QLabel *loopLabel = new QLabel("循环次数 (0=无限循环):", this);
    m_loopSpinBox = new QSpinBox(this);
    m_loopSpinBox->setRange(0, 10000);
    m_loopSpinBox->setValue(0);
    loopLayout->addWidget(loopLabel);
    loopLayout->addWidget(m_loopSpinBox);
    leftLayout->addLayout(loopLayout);

    mainLayout->addLayout(leftLayout, 1);

    // 右侧
    QVBoxLayout *rightLayout = new QVBoxLayout();

    QScrollArea *scrollArea = new QScrollArea(this);
    scrollArea->setWidgetResizable(true);
    m_previewLabel = new QLabel(this);
    m_previewLabel->setAlignment(Qt::AlignCenter);
    m_previewLabel->setMinimumSize(200, 200);
    m_previewLabel->setStyleSheet("background-color: #f0f0f0;");
    scrollArea->setWidget(m_previewLabel);
    rightLayout->addWidget(scrollArea, 1);

    QHBoxLayout *buttonRow2 = new QHBoxLayout();
    m_playButton = new QPushButton("预览图片", this);
    QPushButton *generateButton = new QPushButton("生成 APNG...", this);
    connect(m_playButton, &QPushButton::clicked, this, &MainWindow::togglePreview);
    connect(generateButton, &QPushButton::clicked, this, &MainWindow::generateApng);
    buttonRow2->addWidget(m_playButton);
    buttonRow2->addWidget(generateButton);
    rightLayout->addLayout(buttonRow2);

    mainLayout->addLayout(rightLayout, 2);

    m_previewTimer = new QTimer(this);
    m_previewTimer->setSingleShot(true);
    connect(m_previewTimer, &QTimer::timeout, this, [this]() {
        if (!m_frames.isEmpty()) {
            m_currentPreviewFrame = (m_currentPreviewFrame + 1) % m_frames.size();
            showFrameInPreview(m_currentPreviewFrame);
            updatePreviewTimerInterval();
        }
    });

    statusBar()->showMessage("Ready");

    setAcceptDrops(true);
}

void MainWindow::addFramesFromFiles(const QStringList &fileNames)
{
    if (fileNames.isEmpty())
        return;

    QSize firstSize;
    if (!m_frames.isEmpty())
        firstSize = m_frames.first().image.size();

    for (const QString &fileName : fileNames) {
        QImageReader reader(fileName);
        reader.setAutoTransform(true);
        QImage img = reader.read();
        if (img.isNull()) {
            QMessageBox::warning(this, "Error", "加载图片失败: " + fileName);
            continue;
        }

        if (!firstSize.isValid()) {
            firstSize = img.size();
        } else if (img.size() != firstSize) {
            QMessageBox::warning(this, "Warning",
                                 QString("图片大小 %2x%3 请保持与 %4x%5 一致. \n %1 将被跳过.")
                                     .arg(fileName)
                                     .arg(img.width()).arg(img.height())
                                     .arg(firstSize.width()).arg(firstSize.height()));
            continue;
        }

        if (img.format() != QImage::Format_RGBA8888) {
            img = img.convertToFormat(QImage::Format_RGBA8888);
        }

        FrameItem frame;
        frame.image = img;
        frame.delayNum = m_delaySpinBox->value();
        frame.delayDen = 100;
        m_frames.append(frame);
    }

    refreshFrameList();
}

void MainWindow::addFrames()
{
    QStringList fileNames = QFileDialog::getOpenFileNames(
        this,
        "Select Images",
        QString(),
        "Images (*.png *.jpg *.jpeg *.bmp *.gif *.tiff);;All Files (*)"
    );
    if (fileNames.isEmpty())
        return;
    addFramesFromFiles(fileNames);
}

void MainWindow::removeSelectedFrame()
{
    int row = m_frameList->currentRow();
    if (row >= 0 && row < m_frames.size()) {
        m_frames.removeAt(row);
        refreshFrameList();
    }
}

void MainWindow::moveFrameUp()
{
    int row = m_frameList->currentRow();
    if (row > 0) {
        m_frames.swapItemsAt(row, row - 1);
        refreshFrameList();
        m_frameList->setCurrentRow(row - 1);
    }
}

void MainWindow::moveFrameDown()
{
    int row = m_frameList->currentRow();
    if (row >= 0 && row < m_frames.size() - 1) {
        m_frames.swapItemsAt(row, row + 1);
        refreshFrameList();
        m_frameList->setCurrentRow(row + 1);
    }
}

void MainWindow::generateApng()
{
    if (m_frames.isEmpty()) {
        QMessageBox::information(this, "No Frames", "请添加至少一张图片.");
        return;
    }

    QString savePath = QFileDialog::getSaveFileName(
        this,
        "Save APNG File",
        QString(),
        "APNG Files (*.png);;All Files (*)"
    );

    if (savePath.isEmpty())
        return;

    QString error;
    bool success = ApngGenerator::generate(
        savePath,
        m_frames,
        m_loopSpinBox->value(),
        &error
    );

    if (success) {
        QMessageBox::information(this, "Success", "APNG 保存成功.");
        statusBar()->showMessage("图片已保存在: " + savePath);
    } else {
        QMessageBox::critical(this, "Error", "生成 APNG 失败:\n" + error);
    }
}

void MainWindow::togglePreview()
{
    if (m_frames.isEmpty())
        return;

    if (m_isPreviewing) {
        m_previewTimer->stop();
        m_isPreviewing = false;
        m_playButton->setText("预览图片");
    } else {
        m_isPreviewing = true;
        m_playButton->setText("停止预览");
        m_currentPreviewFrame = 0;
        showFrameInPreview(0);
        updatePreviewTimerInterval();
        m_previewTimer->start();
    }
}

void MainWindow::onFrameSelectionChanged()
{
    int row = m_frameList->currentRow();
    if (row >= 0 && row < m_frames.size()) {
        m_delaySpinBox->blockSignals(true);
        m_delaySpinBox->setValue(m_frames[row].delayNum);
        m_delaySpinBox->blockSignals(false);
    }
}

void MainWindow::onDelayChanged(int value)
{
    int row = m_frameList->currentRow();
    if (row >= 0 && row < m_frames.size()) {
        m_frames[row].delayNum = value;
        QListWidgetItem *item = m_frameList->item(row);
        if (item) {
            QString delayText = QString("延迟: %1/%2 s")
                                    .arg(m_frames[row].delayNum)
                                    .arg(m_frames[row].delayDen);
            item->setText(delayText);
        }
    }
}

void MainWindow::refreshFrameList()
{
    m_frameList->clear();
    for (int i = 0; i < m_frames.size(); ++i) {
        const FrameItem &frame = m_frames[i];
        QPixmap pixmap = QPixmap::fromImage(frame.image).scaled(
            m_frameList->iconSize(),
            Qt::KeepAspectRatio,
            Qt::SmoothTransformation
        );
        QIcon icon(pixmap);
        QString text = QString("Frame %1 - 延迟: %2/%3 s")
                           .arg(i + 1)
                           .arg(frame.delayNum)
                           .arg(frame.delayDen);
        QListWidgetItem *item = new QListWidgetItem(icon, text);
        item->setData(Qt::UserRole, i);
        m_frameList->addItem(item);
    }

    if (!m_frames.isEmpty()) {
        m_frameList->setCurrentRow(0);
    } else {
        m_previewLabel->clear();
    }
}

void MainWindow::showFrameInPreview(int index)
{
    if (index < 0 || index >= m_frames.size())
        return;

    const QImage &img = m_frames[index].image;
    if (img.isNull())
        return;

    QPixmap pixmap = QPixmap::fromImage(img);
    QSize labelSize = m_previewLabel->size();
    if (labelSize.width() < 10 || labelSize.height() < 10)
        return;
    pixmap = pixmap.scaled(labelSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    m_previewLabel->setPixmap(pixmap);
}

void MainWindow::updatePreviewTimerInterval()
{
    if (m_isPreviewing && m_currentPreviewFrame >= 0 && m_currentPreviewFrame < m_frames.size()) {
        const FrameItem &frame = m_frames[m_currentPreviewFrame];
        int delayMs = 100;
        if (frame.delayDen > 0) {
            delayMs = (frame.delayNum * 1000) / frame.delayDen;
        }
        m_previewTimer->start(delayMs);
    }
}

// 实现拖拽事件
void MainWindow::dragEnterEvent(QDragEnterEvent *event)
{
    // 接受所有本地文件拖拽，允许用户放下后看到提示
    if (event->mimeData()->hasUrls()) {
        event->acceptProposedAction();
    } else {
        event->ignore();
    }
}

void MainWindow::dropEvent(QDropEvent *event)
{
    const QList<QUrl> urls = event->mimeData()->urls();
    QStringList supportedFiles;
    QStringList unsupportedFiles;

    // 支持的扩展名列表
    static const QStringList supportedExtensions = {
        "png", "jpg", "jpeg", "bmp", "gif", "tiff"
    };

    for (const QUrl &url : urls) {
        if (!url.isLocalFile()) {
            unsupportedFiles << url.toString();
            continue;
        }

        QString filePath = url.toLocalFile();
        QFileInfo fi(filePath);
        if (fi.isDir()) {
            unsupportedFiles << filePath;  // 文件夹不支持
            continue;
        }

        QString suffix = fi.suffix().toLower();
        if (supportedExtensions.contains(suffix)) {
            supportedFiles << filePath;
        } else {
            unsupportedFiles << filePath;
        }
    }

    // 先处理不支持的，给出友好提示
    if (!unsupportedFiles.isEmpty()) {
        QString message = "以下文件不是支持的图片格式，已忽略：\n\n";
        for (const QString &file : unsupportedFiles) {
            message += "• " + QFileInfo(file).fileName() + "\n";
        }
        message += "\n支持的格式：PNG、JPEG、BMP、GIF、TIFF";
        QMessageBox::warning(this, "不支持的文件", message);
    }

    // 处理支持的图片文件
    if (!supportedFiles.isEmpty()) {
        addFramesFromFiles(supportedFiles);
        event->acceptProposedAction();
    } else {
        event->ignore();
    }
}