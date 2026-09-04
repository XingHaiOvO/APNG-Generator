#ifndef MAINWINDOW_H
#define MAINWINDOW_H

#include <QMainWindow>
#include <QVector>
#include <QListWidget>
#include <QLabel>
#include <QTimer>
#include <QSpinBox>
#include <QPushButton>
#include <QDragEnterEvent>
#include <QDropEvent>
#include <QMimeData>
#include "FrameItem.h"

class MainWindow : public QMainWindow
{
    Q_OBJECT

public:
    explicit MainWindow(QWidget *parent = nullptr);
    ~MainWindow();

private slots:
    void addFrames();
    void removeSelectedFrame();
    void moveFrameUp();
    void moveFrameDown();
    void generateApng();
    void togglePreview();
    void onFrameSelectionChanged();
    void onDelayChanged(int value);
    void addFramesFromFiles(const QStringList &fileNames);

protected:
    void dragEnterEvent(QDragEnterEvent *event) override;
    void dropEvent(QDropEvent *event) override;

private:
    void setupUi();
    void refreshFrameList();
    void showFrameInPreview(int index);
    void updatePreviewTimerInterval();

    QVector<FrameItem> m_frames;
    QListWidget *m_frameList;
    QLabel *m_previewLabel;
    QTimer *m_previewTimer;
    int m_currentPreviewFrame;
    bool m_isPreviewing;

    QSpinBox *m_delaySpinBox;
    QSpinBox *m_loopSpinBox;
    QPushButton *m_playButton;
};

#endif // MAINWINDOW_H