import { NgFor } from '@angular/common';
import { Component, OnInit } from '@angular/core';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { DocumentRecord, DocumentsService } from '../../services/documents.service';

@Component({
  selector: 'app-upload-documents',
  standalone: true,
  imports: [NgFor, RouterLink],
  template: `
    <div class="page">
      <h1>Upload your documents</h1>
      <p>Upload all three required documents. Once all three are in, our fraud/forensics check
      kicks off automatically in the background.</p>

      <div *ngFor="let type of requiredTypes">
        <label>{{ type }}</label>
        <input type="file" (change)="onFileSelected($event, type)" [disabled]="uploading" />
      </div>

      <ul>
        <li *ngFor="let doc of uploadedDocuments">{{ doc.type }} — {{ doc.status }}</li>
      </ul>

      <a [routerLink]="['/applications', applicationId, 'status']">Continue to status tracking</a>
    </div>
  `,
})
export class UploadDocumentsComponent implements OnInit {
  applicationId = '';
  requiredTypes = ['IdentityProof', 'IncomeProof', 'BankStatement'];
  uploadedDocuments: DocumentRecord[] = [];
  uploading = false;

  constructor(
    private readonly route: ActivatedRoute,
    private readonly router: Router,
    private readonly documents: DocumentsService,
  ) {}

  ngOnInit(): void {
    this.applicationId = this.route.snapshot.paramMap.get('id') ?? '';
    this.refresh();
  }

  onFileSelected(event: Event, type: string): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;

    this.uploading = true;
    this.documents.uploadDocument(this.applicationId, type, file).subscribe({
      next: () => {
        this.uploading = false;
        this.refresh();
      },
      error: (err) => {
        this.uploading = false;
        console.error(err);
      },
    });
  }

  private refresh(): void {
    this.documents.getDocumentsForApplication(this.applicationId).subscribe((docs) => (this.uploadedDocuments = docs));
  }
}
